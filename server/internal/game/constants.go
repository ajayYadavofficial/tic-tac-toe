package game

const (
	// Match tick rate (server updates per second)
	TickRate = 10

	// WebSocket opcodes
	OpCodeMove   = 1 // client → server: player makes a move
	OpCodeState  = 2 // server → client: broadcast game state
	OpCodeResult = 3 // server → client: game over with winner/draw
	OpCodeError  = 4 // server → client: invalid move or error
	OpCodeResign = 5 // client → server: player resigns (back button / leave)

	// Board marks
	MarkEmpty = ""
	MarkX     = "X"
	MarkO     = "O"

	// Match status strings
	StatusWaiting  = "waiting"   // waiting for second player
	StatusPlaying  = "playing"   // game in progress
	StatusGameOver = "game_over" // game ended

	// Result types
	ResultWin  = "win"
	ResultDraw = "draw"

	// Game modes
	GameModeClassic = "classic"
	GameModeBlitz   = "blitz"

	// TurnTimer disabled sentinel
	TurnTimerDisabled = -1

	// Blitz mode: seconds per turn before auto-forfeit
	BlitzTurnSecs = 10

	// Board size
	BoardSize = 9

	// Player limits
	MinPlayers = 2
	MaxPlayers = 2

	// Scoring
	ScoreWin  = 200
	ScoreDraw = 50
	ScoreLoss = 0

	// Nakama Storage keys for player stats
	StatsCollection = "stats"
	StatsKey        = "player"

	// Nakama Leaderboard ID
	LeaderboardID = "global_score"

	// Account cleanup — configurable interval in seconds.
	// The worker runs every CleanupIntervalSec and removes stale accounts
	// whose last-active timestamp is older than CleanupIntervalSec.
	CleanupIntervalSec = 1200 // 20 minutes

	// Storage keys for last-active tracking
	LastActiveCollection = "activity"
	LastActiveKey        = "last_active"
)
