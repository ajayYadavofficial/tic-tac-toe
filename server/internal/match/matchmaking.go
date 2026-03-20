package match

import (
	"context"
	"database/sql"
	"strconv"

	"github.com/heroiclabs/nakama-common/runtime"
)

// OnMatchmakerMatched is called by Nakama when two players are paired.
// It creates an authoritative match and returns the match ID so both
// players are automatically joined via the matchmaker token.
func OnMatchmakerMatched(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, entries []runtime.MatchmakerEntry) (string, error) {
	// Extract templateId (integer stored as string property) from the first entry.
	// Defaults to template ID 1 (Classic) if absent or unparseable.
	templateId := 1
	if len(entries) > 0 {
		if props := entries[0].GetProperties(); props != nil {
			if tidStr, ok := props["templateId"].(string); ok && tidStr != "" {
				if parsed, err := strconv.Atoi(tidStr); err == nil {
					templateId = parsed
				}
			}
		}
	}

	matchID, err := nk.MatchCreate(ctx, "tic_tac_toe", map[string]interface{}{
		"templateId": templateId,
	})
	if err != nil {
		logger.Error("matchmaker: failed to create match: %v", err)
		return "", err
	}
	logger.Info("matchmaker: created match %s for %d players (templateId: %d)", matchID, len(entries), templateId)
	return matchID, nil
}
