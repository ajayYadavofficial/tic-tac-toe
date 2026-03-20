package match

import (
	"context"
	"database/sql"
	"encoding/json"

	"github.com/heroiclabs/nakama-common/runtime"

	"github.com/ajayyadav/tictactoe/internal/game"
)

// CalcStatsDeltas returns the stats deltas for both players given a match result.
// Pure function — no side effects, easy to unit test.
func CalcStatsDeltas(winner, playerX, playerO string) (xDelta, oDelta game.PlayerStats) {
	if winner == "" {
		// Draw
		xDelta = game.PlayerStats{Draws: 1, Score: game.ScoreDraw}
		oDelta = game.PlayerStats{Draws: 1, Score: game.ScoreDraw}
	} else if winner == playerX {
		xDelta = game.PlayerStats{Wins: 1, Score: game.ScoreWin}
		oDelta = game.PlayerStats{Losses: 1, Score: game.ScoreLoss}
	} else {
		xDelta = game.PlayerStats{Losses: 1, Score: game.ScoreLoss}
		oDelta = game.PlayerStats{Wins: 1, Score: game.ScoreWin}
	}
	return
}

// OnMatchEnd persists player stats and updates the global leaderboard.
func OnMatchEnd(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, db *sql.DB, state interface{}) {
	s, ok := state.(*game.MatchState)
	if !ok || s == nil {
		return
	}
	if s.PlayerX == "" || s.PlayerO == "" {
		return // match never had two players
	}

	xDelta, oDelta := CalcStatsDeltas(s.Winner, s.PlayerX, s.PlayerO)

	players := []struct {
		userID string
		name   string
		delta  game.PlayerStats
	}{
		{s.PlayerX, s.PlayerXName, xDelta},
		{s.PlayerO, s.PlayerOName, oDelta},
	}

	const maxRetries = 3
	for _, p := range players {
		var updated game.PlayerStats
		for attempt := range maxRetries {
			stats, version := readStatsWithVersion(ctx, logger, nk, p.userID)
			updated = game.PlayerStats{
				Wins:   stats.Wins + p.delta.Wins,
				Losses: stats.Losses + p.delta.Losses,
				Draws:  stats.Draws + p.delta.Draws,
				Score:  stats.Score + p.delta.Score,
			}
			if writeStatsConditional(ctx, logger, nk, p.userID, updated, version) {
				break
			}
			if attempt == maxRetries-1 {
				logger.Error("stats write for %s failed after %d retries", p.userID, maxRetries)
			}
		}
		writeLeaderboard(ctx, logger, nk, p.userID, p.name, int64(updated.Score))
	}
}

// readStatsWithVersion returns player stats and the storage version string.
// The version is used for optimistic concurrency control on writes.
func readStatsWithVersion(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, userID string) (game.PlayerStats, string) {
	reads := []*runtime.StorageRead{{
		Collection: game.StatsCollection,
		Key:        game.StatsKey,
		UserID:     userID,
	}}
	records, err := nk.StorageRead(ctx, reads)
	if err != nil {
		logger.Error("failed to read stats for %s: %v", userID, err)
		return game.PlayerStats{}, ""
	}
	if len(records) == 0 {
		return game.PlayerStats{}, ""
	}
	var stats game.PlayerStats
	if err := json.Unmarshal([]byte(records[0].Value), &stats); err != nil {
		logger.Error("failed to unmarshal stats for %s: %v", userID, err)
		return game.PlayerStats{}, ""
	}
	return stats, records[0].Version
}

// writeStatsConditional writes stats with version-conditional check to prevent
// lost-update races when two matches end simultaneously for the same player.
// Returns true on success, false on version conflict (caller should retry).
func writeStatsConditional(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, userID string, stats game.PlayerStats, version string) bool {
	data, _ := json.Marshal(stats)
	write := &runtime.StorageWrite{
		Collection:      game.StatsCollection,
		Key:             game.StatsKey,
		UserID:          userID,
		Value:           string(data),
		PermissionRead:  2, // public read
		PermissionWrite: 0, // server-only write
	}
	// If we have a version from a previous read, use it for optimistic locking.
	// Empty version means first write (new record) — no condition needed.
	if version != "" {
		write.Version = version
	}
	if _, err := nk.StorageWrite(ctx, []*runtime.StorageWrite{write}); err != nil {
		logger.Warn("stats write conflict for %s (version %s): %v", userID, version, err)
		return false
	}
	return true
}

func writeLeaderboard(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, userID, username string, score int64) {
	if _, err := nk.LeaderboardRecordWrite(ctx, game.LeaderboardID, userID, username, score, 0, nil, nil); err != nil {
		logger.Error("failed to write leaderboard for %s: %v", userID, err)
	}
}
