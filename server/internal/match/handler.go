package match

import (
	"context"
	"database/sql"
	"encoding/json"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"

	"github.com/ajayyadav/tictactoe/internal/game"
)

const disconnectGracePeriod = 30 // seconds before a disconnected player forfeits

// Handler implements the Nakama runtime.Match interface.
type Handler struct{}

func (h *Handler) MatchInit(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, params map[string]interface{}) (interface{}, int, string) {
	state := game.NewMatchState()

	// Read templateId from matchmaker params to configure the game mode.
	// Nakama preserves Go types in MatchCreate params (no JSON round-trip),
	// so the value may arrive as int, float64, or other numeric type.
	if tidRaw, ok := params["templateId"]; ok {
		var tid int
		switch v := tidRaw.(type) {
		case int:
			tid = v
		case float64:
			tid = int(v)
		case int64:
			tid = int(v)
		default:
			logger.Warn("templateId has unexpected type %T, defaulting to Classic", tidRaw)
		}
		if tmpl := game.TemplateByID(tid); tmpl != nil {
			state.GameMode = tmpl.Variant
			if tmpl.TurnSecs > 0 {
				state.TurnTimer = tmpl.TurnSecs
			}
			logger.Info("Match created with template %d (%s), turnSecs=%d", tid, tmpl.Variant, tmpl.TurnSecs)
		}
	}

	label, _ := json.Marshal(game.MatchLabel{Open: 1, GameMode: state.GameMode})
	return state, game.TickRate, string(label)
}

func (h *Handler) MatchJoinAttempt(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, dispatcher runtime.MatchDispatcher, tick int64, state interface{}, presence runtime.Presence, metadata map[string]string) (interface{}, bool, string) {
	s := state.(*game.MatchState)
	uid := presence.GetUserId()

	// Allow rejoining if the player was already assigned a slot.
	if uid == s.PlayerX || uid == s.PlayerO {
		return s, true, ""
	}

	// Allow new players only while the match is still waiting for someone.
	if s.PlayerX == "" || s.PlayerO == "" {
		return s, true, ""
	}

	return s, false, "match is full"
}

func (h *Handler) MatchJoin(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, dispatcher runtime.MatchDispatcher, tick int64, state interface{}, presences []runtime.Presence) interface{} {
	s := state.(*game.MatchState)
	next := *s

	for _, p := range presences {
		uid := p.GetUserId()

		// Refresh last-active timestamp so the cleanup worker won't reap this account.
		TouchLastActive(ctx, logger, nk, uid)

		// Clear any disconnect record for a returning player.
		delete(next.Disconnected, uid)

		if next.PlayerX == "" {
			next.PlayerX = uid
			logger.Info("Player X joined: %s", uid)
		} else if next.PlayerO == "" && uid != next.PlayerX {
			next.PlayerO = uid
			logger.Info("Player O joined: %s", uid)
		} else {
			logger.Info("Player %s rejoined", uid)
		}
	}

	// Look up display names once both players are assigned.
	if next.PlayerX != "" && next.PlayerO != "" {
		uids := []string{next.PlayerX, next.PlayerO}
		if users, err := nk.UsersGetId(ctx, uids, nil); err == nil {
			for _, u := range users {
				// Username is the unique field set by the player; prefer it.
				// Fall back to displayName (also set in rpcUpdateUsername), then raw user ID prefix.
				name := u.GetUsername()
				if name == "" {
					name = u.GetDisplayName()
				}
				if u.GetId() == next.PlayerX {
					next.PlayerXName = name
				} else {
					next.PlayerOName = name
				}
			}
		} else {
			logger.Error("failed to fetch user display names: %v", err)
		}
	}

	if next.PlayerX != "" && next.PlayerO != "" && next.Status == game.StatusWaiting {
		next.Status = game.StatusPlaying
		if next.TurnTimer > 0 {
			next.TurnStartedAt = time.Now().Unix()
		}
		label, _ := json.Marshal(game.MatchLabel{Open: 0, GameMode: next.GameMode})
		if err := dispatcher.MatchLabelUpdate(string(label)); err != nil {
			logger.Error("failed to update match label: %v", err)
		}
	}

	// Always broadcast the current state so a rejoining player catches up.
	broadcastState(dispatcher, logger, &next)

	return &next
}

func (h *Handler) MatchLeave(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, dispatcher runtime.MatchDispatcher, tick int64, state interface{}, presences []runtime.Presence) interface{} {
	s := state.(*game.MatchState)
	if s.Status != game.StatusPlaying {
		return s
	}

	next := *s
	if next.Disconnected == nil {
		next.Disconnected = make(map[string]int64)
	}
	now := time.Now().Unix()
	for _, p := range presences {
		uid := p.GetUserId()
		next.Disconnected[uid] = now
		logger.Info("Player %s disconnected — grace period started", uid)
	}
	return &next
}

// SAFETY: Nakama guarantees MatchLoop runs single-threaded per match.
// All state mutations below are safe without locks. Do NOT spawn goroutines
// from this function — any concurrent access to MatchState would cause races.
func (h *Handler) MatchLoop(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, dispatcher runtime.MatchDispatcher, tick int64, state interface{}, messages []runtime.MatchData) interface{} {
	s := state.(*game.MatchState)

	// --- Disconnection grace period check ---
	if s.Status == game.StatusPlaying && len(s.Disconnected) > 0 {
		now := time.Now().Unix()
		for uid, disconnectAt := range s.Disconnected {
			if now-disconnectAt >= disconnectGracePeriod {
				logger.Info("Player %s exceeded grace period — forfeiting", uid)
				next := *s
				next.Status = game.StatusGameOver
				if uid == next.PlayerX {
					next.Winner = next.PlayerO
				} else {
					next.Winner = next.PlayerX
				}
				broadcastState(dispatcher, logger, &next)
				rm := game.ResultMsg{
					Winner:      next.Winner,
					Result:      game.ResultWin,
					Board:       next.Board,
					PlayerX:     next.PlayerX,
					PlayerO:     next.PlayerO,
					PlayerXName: next.PlayerXName,
					PlayerOName: next.PlayerOName,
				}
				data, _ := json.Marshal(rm)
				if err := dispatcher.BroadcastMessage(game.OpCodeResult, data, nil, nil, true); err != nil {
					logger.Error("failed to broadcast forfeit result: %v", err)
				}
				OnMatchEnd(ctx, logger, nk, db, &next)
				return nil // terminate match
			}
		}
	}

	// --- Process incoming moves BEFORE timer check ---
	// This prevents the race where a valid move arrives in the same tick as
	// the timer expiry. By processing moves first, a last-second move is
	// accepted and the timer is reset, avoiding unfair forfeits.
	for _, msg := range messages {
		if msg.GetOpCode() != game.OpCodeMove {
			continue
		}

		var move game.MoveMsg
		if err := json.Unmarshal(msg.GetData(), &move); err != nil {
			sendError(dispatcher, logger, msg, "invalid message format")
			continue
		}

		if err := game.ValidateMove(s, msg.GetUserId(), move.Position); err != nil {
			sendError(dispatcher, logger, msg, err.Error())
			continue
		}

		next := game.ApplyMove(s, move.Position)

		// Reset turn timer for the next player's turn
		if next.TurnTimer > 0 {
			next.TurnStartedAt = time.Now().Unix()
		}

		result, winnerMark := game.GetGameResult(next.Board)
		if result != "" {
			next.Status = game.StatusGameOver
			if result == game.ResultWin {
				next.Winner = game.MarkToUserID(next, winnerMark)
			}

			broadcastState(dispatcher, logger, next)

			rm := game.ResultMsg{
				Winner:      next.Winner,
				Result:      result,
				Board:       next.Board,
				PlayerX:     next.PlayerX,
				PlayerO:     next.PlayerO,
				PlayerXName: next.PlayerXName,
				PlayerOName: next.PlayerOName,
			}
			data, _ := json.Marshal(rm)
			if err := dispatcher.BroadcastMessage(game.OpCodeResult, data, nil, nil, true); err != nil {
				logger.Error("failed to broadcast result: %v", err)
			}

			OnMatchEnd(ctx, logger, nk, db, next)
		} else {
			broadcastState(dispatcher, logger, next)
		}

		s = next
	}

	// Early exit if a move just ended the game
	if s.Status == game.StatusGameOver {
		return nil
	}

	// --- Turn timer check (Blitz mode) ---
	// Runs AFTER move processing so a last-second move resets the timer
	// before we check for expiry, preventing unfair forfeits.
	if s.Status == game.StatusPlaying && s.TurnTimer > 0 && s.TurnStartedAt > 0 {
		now := time.Now().Unix()
		if now-s.TurnStartedAt >= int64(s.TurnTimer) {
			next := *s
			next.Status = game.StatusGameOver
			if next.Turn == game.MarkX {
				next.Winner = next.PlayerO
			} else {
				next.Winner = next.PlayerX
			}
			logger.Info("Turn timer expired for %s — %s wins by timeout", next.Turn, next.Winner)
			broadcastState(dispatcher, logger, &next)
			rm := game.ResultMsg{
				Winner:      next.Winner,
				Result:      game.ResultWin,
				Board:       next.Board,
				PlayerX:     next.PlayerX,
				PlayerO:     next.PlayerO,
				PlayerXName: next.PlayerXName,
				PlayerOName: next.PlayerOName,
			}
			data, _ := json.Marshal(rm)
			if err := dispatcher.BroadcastMessage(game.OpCodeResult, data, nil, nil, true); err != nil {
				logger.Error("failed to broadcast timeout result: %v", err)
			}
			OnMatchEnd(ctx, logger, nk, db, &next)
			return nil
		}
	}

	// --- Periodic state re-broadcast (every 10 ticks = ~1s) ---
	if s.Status != game.StatusGameOver && tick%10 == 0 {
		broadcastState(dispatcher, logger, s)
	}

	return s
}

func (h *Handler) MatchTerminate(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, dispatcher runtime.MatchDispatcher, tick int64, state interface{}, graceSeconds int) interface{} {
	return state
}

func (h *Handler) MatchSignal(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, dispatcher runtime.MatchDispatcher, tick int64, state interface{}, data string) (interface{}, string) {
	return state, ""
}

// --- helpers ---

func broadcastState(dispatcher runtime.MatchDispatcher, logger runtime.Logger, s *game.MatchState) {
	turnSecs := 0
	if s.TurnTimer > 0 {
		turnSecs = s.TurnTimer
	}
	msg := game.StateMsg{
		Board:         s.Board,
		Turn:          s.Turn,
		Status:        s.Status,
		PlayerX:       s.PlayerX,
		PlayerO:       s.PlayerO,
		PlayerXName:   s.PlayerXName,
		PlayerOName:   s.PlayerOName,
		TurnSecs:      turnSecs,
		TurnStartedAt: s.TurnStartedAt,
	}
	data, _ := json.Marshal(msg)
	if err := dispatcher.BroadcastMessage(game.OpCodeState, data, nil, nil, true); err != nil {
		logger.Error("failed to broadcast state: %v", err)
	}
}

func sendError(dispatcher runtime.MatchDispatcher, logger runtime.Logger, presence runtime.Presence, message string) {
	em := game.ErrorMsg{Message: message}
	data, _ := json.Marshal(em)
	targets := []runtime.Presence{presence}
	if err := dispatcher.BroadcastMessage(game.OpCodeError, data, targets, nil, false); err != nil {
		logger.Error("failed to send error: %v", err)
	}
}
