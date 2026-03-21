package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"

	"github.com/heroiclabs/nakama-common/runtime"

	"github.com/ajayyadav/tictactoe/internal/game"
	"github.com/ajayyadav/tictactoe/internal/match"
)

// main is required for `go build` but unused in plugin mode (-buildmode=plugin).
func main() {}

// InitModule is the entry point called by Nakama when the plugin loads.
func InitModule(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, initializer runtime.Initializer) error {
	logger.Info("Tic-Tac-Toe plugin initializing")

	// Create the global leaderboard (idempotent — safe to call on every startup).
	if err := nk.LeaderboardCreate(ctx, game.LeaderboardID, false, "desc", "set", "", nil); err != nil {
		logger.Warn("leaderboard create (may already exist): %v", err)
	}

	if err := initializer.RegisterMatch("tic_tac_toe", func(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule) (runtime.Match, error) {
		return &match.Handler{}, nil
	}); err != nil {
		return err
	}

	if err := initializer.RegisterRpc("create_match", rpcCreateMatch); err != nil {
		return err
	}

	if err := initializer.RegisterRpc("list_matches", rpcListMatches); err != nil {
		return err
	}

	if err := initializer.RegisterRpc("list_templates", rpcListTemplates); err != nil {
		return err
	}

	if err := initializer.RegisterRpc("update_username", rpcUpdateUsername); err != nil {
		return err
	}

	if err := initializer.RegisterRpc("release_username", rpcReleaseUsername); err != nil {
		return err
	}

	if err := initializer.RegisterRpc("player_stats", rpcPlayerStats); err != nil {
		return err
	}

	if err := initializer.RegisterRpc("get_leaderboard", rpcGetLeaderboard); err != nil {
		return err
	}

	if err := initializer.RegisterMatchmakerMatched(match.OnMatchmakerMatched); err != nil {
		return err
	}

	// Start background cleanup worker for stale disconnected accounts.
	match.RegisterCleanupWorker(ctx, logger, db, nk)

	logger.Info("Tic-Tac-Toe plugin initialized successfully")
	return nil
}

func rpcCreateMatch(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	// Parse optional templateId from request payload; default to Classic (1).
	templateId := 1
	if payload != "" {
		var req struct {
			TemplateID int `json:"template_id"`
		}
		if err := json.Unmarshal([]byte(payload), &req); err == nil && req.TemplateID > 0 {
			templateId = req.TemplateID
		}
	}
	matchID, err := nk.MatchCreate(ctx, "tic_tac_toe", map[string]interface{}{
		"templateId": templateId,
	})
	if err != nil {
		logger.Error("failed to create match: %v", err)
		return "", err
	}
	resp, _ := json.Marshal(map[string]string{"match_id": matchID})
	return string(resp), nil
}

func rpcListMatches(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	limit := 20
	authoritative := true
	minSize := 0
	maxSize := 1
	query := "+label.open:1"

	matches, err := nk.MatchList(ctx, limit, authoritative, "", &minSize, &maxSize, query)
	if err != nil {
		logger.Error("failed to list matches: %v", err)
		return "", err
	}

	type matchInfo struct {
		MatchID string `json:"match_id"`
		Size    int    `json:"size"`
	}

	result := make([]matchInfo, 0, len(matches))
	for _, m := range matches {
		result = append(result, matchInfo{
			MatchID: m.GetMatchId(),
			Size:    int(m.GetSize()),
		})
	}

	resp, _ := json.Marshal(map[string]interface{}{"matches": result})
	return string(resp), nil
}

// rpcListTemplates returns all available game templates.
// Clients call this on lobby load to populate the template cards.
func rpcListTemplates(_ context.Context, _ runtime.Logger, _ *sql.DB, _ runtime.NakamaModule, _ string) (string, error) {
	resp, _ := json.Marshal(map[string]interface{}{"templates": game.AllTemplates})
	return string(resp), nil
}

// rpcUpdateUsername sets the caller's Nakama display name.
// Payload: {"username": "PlayerName"}
func rpcUpdateUsername(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	var req struct {
		Username string `json:"username"`
	}
	if err := json.Unmarshal([]byte(payload), &req); err != nil || req.Username == "" {
		return "", runtime.NewError("username is required", 3)
	}
	// Normalize to lowercase so "Kala" and "kAlA" are the same.
	req.Username = strings.ToLower(req.Username)

	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("unauthenticated", 16)
	}
	// If the user already owns this username, return success — no update needed.
	if accounts, err := nk.AccountGetId(ctx, userID); err == nil {
		if strings.EqualFold(accounts.GetUser().GetUsername(), req.Username) {
			resp, _ := json.Marshal(map[string]string{"status": "ok"})
			return string(resp), nil
		}
	}
	// Set username (unique, DB-enforced) AND displayName so both fields carry the chosen name.
	if err := nk.AccountUpdateId(ctx, userID, req.Username, nil, req.Username, "", "", "", ""); err != nil {
		logger.Error("failed to update username for %s: %v", userID, err)
		return "", err
	}
	resp, _ := json.Marshal(map[string]string{"status": "ok"})
	return string(resp), nil
}

// rpcPlayerStats returns the caller's win/loss/draw/score stats.
func rpcPlayerStats(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("unauthenticated", 16)
	}
	reads := []*runtime.StorageRead{{
		Collection: game.StatsCollection,
		Key:        game.StatsKey,
		UserID:     userID,
	}}
	records, err := nk.StorageRead(ctx, reads)
	if err != nil {
		logger.Error("failed to read stats for %s: %v", userID, err)
		return "", err
	}
	if len(records) == 0 {
		resp, _ := json.Marshal(game.PlayerStats{})
		return string(resp), nil
	}
	return records[0].Value, nil
}

// rpcGetLeaderboard returns the top players from the global leaderboard.
func rpcGetLeaderboard(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	records, _, _, _, err := nk.LeaderboardRecordsList(ctx, game.LeaderboardID, nil, 20, "", 0)
	if err != nil {
		logger.Error("failed to list leaderboard: %v", err)
		return "", err
	}
	type entry struct {
		UserID   string `json:"user_id"`
		Username string `json:"username"`
		Score    int64  `json:"score"`
		Rank     int64  `json:"rank"`
	}
	entries := make([]entry, 0, len(records))
	for _, r := range records {
		entries = append(entries, entry{
			UserID:   r.OwnerId,
			Username: r.Username.GetValue(),
			Score:    r.Score,
			Rank:     r.Rank,
		})
	}
	resp, _ := json.Marshal(map[string]interface{}{"records": entries})
	return string(resp), nil
}

// rpcReleaseUsername frees the username AND immediately deletes the account
// (stats, leaderboard entry, and the Nakama account itself). Called on logout.
func rpcReleaseUsername(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("unauthenticated", 16)
	}
	// Delete stats, leaderboard entry, and account.
	match.DeleteAccount(ctx, logger, nk, userID)
	logger.Info("Account %s deleted on logout", userID)

	resp, _ := json.Marshal(map[string]string{"status": "ok"})
	return string(resp), nil
}
