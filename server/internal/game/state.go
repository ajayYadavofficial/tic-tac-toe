package game

// MatchState holds all server-side game state for a single match.
// GameMode and TurnTimer are extensibility hooks — currently unused;
// future timer/leaderboard features fill them in without touching match loop.
type MatchState struct {
	Board         [BoardSize]string // indices 0–8 (row-major)
	PlayerX       string            // Nakama user ID of X player
	PlayerO       string            // Nakama user ID of O player
	PlayerXName   string            // display name of X player
	PlayerOName   string            // display name of O player
	Turn          string            // MarkX or MarkO
	Status        string            // StatusWaiting / StatusPlaying / StatusGameOver
	Winner        string            // user ID of winner, or "" for draw
	GameMode      string            // "classic" or "blitz"
	TurnTimer     int               // -1 = disabled, >0 = seconds per turn
	TurnStartedAt int64             // unix timestamp when current turn started (0 = not set)
	Disconnected  map[string]int64  // userID → unix timestamp of disconnect
}

// NewMatchState returns a fresh, waiting match state.
func NewMatchState() *MatchState {
	return &MatchState{
		Board:        [BoardSize]string{},
		Turn:         MarkX,
		Status:       StatusWaiting,
		GameMode:     GameModeClassic,
		TurnTimer:    TurnTimerDisabled,
		Disconnected: make(map[string]int64),
	}
}

// --- Wire messages (JSON over WebSocket) ---

// MoveMsg is sent by the client to make a move.
type MoveMsg struct {
	Position int `json:"position"` // 0–8
}

// StateMsg is broadcast to all clients after every state change.
type StateMsg struct {
	Board         [BoardSize]string `json:"board"`
	Turn          string            `json:"turn"`             // "X" or "O"
	Status        string            `json:"status"`
	PlayerX       string            `json:"player_x"`
	PlayerO       string            `json:"player_o"`
	PlayerXName   string            `json:"player_x_name"`    // display name
	PlayerOName   string            `json:"player_o_name"`    // display name
	TurnSecs      int               `json:"turn_secs"`        // 0 = no timer, >0 = seconds per turn
	TurnStartedAt int64             `json:"turn_started_at"`  // unix timestamp (0 if no timer)
}

// ResultMsg is sent when the game ends.
type ResultMsg struct {
	Winner      string            `json:"winner"`        // user ID or "" for draw
	Result      string            `json:"result"`        // "win" or "draw"
	Board       [BoardSize]string `json:"board"`         // final board state
	PlayerX     string            `json:"player_x"`      // user ID
	PlayerO     string            `json:"player_o"`      // user ID
	PlayerXName string            `json:"player_x_name"` // display name
	PlayerOName string            `json:"player_o_name"` // display name
}

// PlayerStats tracks per-player win/loss/draw counts and score.
// Stored in Nakama Storage (collection: "stats", key: "player").
type PlayerStats struct {
	Wins   int `json:"wins"`
	Losses int `json:"losses"`
	Draws  int `json:"draws"`
	Score  int `json:"score"`
}

// ErrorMsg is sent to the client that made an invalid move.
type ErrorMsg struct {
	Message string `json:"message"`
}

// MatchLabel is stored in Nakama's match listing so clients can discover open rooms.
type MatchLabel struct {
	Open     int    `json:"open"`      // 1 = waiting for player, 0 = in progress
	GameMode string `json:"game_mode"` // "classic"
}
