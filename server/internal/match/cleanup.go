package match

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"

	"github.com/ajayyadav/tictactoe/internal/game"
)

// TouchLastActive writes the current timestamp to the user's last-active record.
// Called on match join to keep the account alive.
func TouchLastActive(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, userID string) {
	data, _ := json.Marshal(map[string]int64{"ts": time.Now().Unix()})
	write := &runtime.StorageWrite{
		Collection:      game.LastActiveCollection,
		Key:             game.LastActiveKey,
		UserID:          userID,
		Value:           string(data),
		PermissionRead:  0, // server-only
		PermissionWrite: 0, // server-only
	}
	if _, err := nk.StorageWrite(ctx, []*runtime.StorageWrite{write}); err != nil {
		logger.Error("failed to touch last-active for %s: %v", userID, err)
	}
}

// DeleteAccountData removes a user's stats, last-active record, and leaderboard entry.
// Called on explicit logout (immediate cleanup).
func DeleteAccountData(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, userID string) {
	// Delete stats
	deletes := []*runtime.StorageDelete{
		{Collection: game.StatsCollection, Key: game.StatsKey, UserID: userID},
		{Collection: game.LastActiveCollection, Key: game.LastActiveKey, UserID: userID},
	}
	if err := nk.StorageDelete(ctx, deletes); err != nil {
		logger.Error("failed to delete storage for %s: %v", userID, err)
	}

	// Delete leaderboard entry
	if err := nk.LeaderboardRecordDelete(ctx, game.LeaderboardID, userID); err != nil {
		logger.Error("failed to delete leaderboard for %s: %v", userID, err)
	}
}

// DeleteAccount fully removes a user account from Nakama (stats, leaderboard, and account record).
func DeleteAccount(ctx context.Context, logger runtime.Logger, nk runtime.NakamaModule, userID string) {
	DeleteAccountData(ctx, logger, nk, userID)

	// Delete the Nakama account itself (recorded = false means don't mark as tombstone)
	if err := nk.AccountDeleteId(ctx, userID, false); err != nil {
		logger.Error("failed to delete account %s: %v", userID, err)
	}
}

// RegisterCleanupWorker registers an RPC that Nakama's built-in CRON system
// or a simple goroutine ticker calls periodically. We use the InitModule
// callback to start a background ticker.
func RegisterCleanupWorker(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule) {
	interval := time.Duration(game.CleanupIntervalSec) * time.Second
	logger.Info("Starting account cleanup worker (interval=%v)", interval)

	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				logger.Info("Cleanup worker stopping — context cancelled")
				return
			case <-ticker.C:
				runCleanup(logger, nk)
			}
		}
	}()
}

func runCleanup(logger runtime.Logger, nk runtime.NakamaModule) {
	ctx := context.Background()
	threshold := time.Now().Unix() - int64(game.CleanupIntervalSec)

	// List all last-active records. We page through with a cursor.
	var cursor string
	cleaned := 0

	for {
		// callerID="" (system), userID="" (all users), collection, limit, cursor
		objects, nextCursor, err := nk.StorageList(ctx, "", "", game.LastActiveCollection, 100, cursor)
		if err != nil {
			logger.Error("cleanup: failed to list last-active records: %v", err)
			return
		}

		for _, obj := range objects {
			var record struct {
				TS int64 `json:"ts"`
			}
			if err := json.Unmarshal([]byte(obj.Value), &record); err != nil {
				logger.Warn("cleanup: invalid last-active record for %s: %v", obj.UserId, err)
				continue
			}

			if record.TS < threshold {
				logger.Info("cleanup: removing stale account %s (last active %s)",
					obj.UserId, time.Unix(record.TS, 0).Format(time.RFC3339))
				DeleteAccount(ctx, logger, nk, obj.UserId)
				cleaned++
			}
		}

		if nextCursor == "" {
			break
		}
		cursor = nextCursor
	}

	if cleaned > 0 {
		logger.Info(fmt.Sprintf("cleanup: removed %d stale accounts", cleaned))
	}
}
