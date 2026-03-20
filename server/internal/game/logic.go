package game

import (
	"fmt"
	"time"
)

// winLines are all winning combinations on a 3×3 board.
var winLines = [8][3]int{
	{0, 1, 2}, // top row
	{3, 4, 5}, // middle row
	{6, 7, 8}, // bottom row
	{0, 3, 6}, // left col
	{1, 4, 7}, // middle col
	{2, 5, 8}, // right col
	{0, 4, 8}, // diagonal
	{2, 4, 6}, // anti-diagonal
}

// ValidateMove returns an error if the move is not legal.
func ValidateMove(state *MatchState, userID string, pos int) error {
	if state.Status != StatusPlaying {
		return fmt.Errorf("game is not in progress")
	}
	if pos < 0 || pos >= BoardSize {
		return fmt.Errorf("position %d out of range", pos)
	}
	if state.Board[pos] != MarkEmpty {
		return fmt.Errorf("position %d already occupied", pos)
	}
	mark := playerMark(state, userID)
	if mark == MarkEmpty {
		return fmt.Errorf("user is not a player in this match")
	}
	if mark != state.Turn {
		return fmt.Errorf("not your turn")
	}
	// Reject moves after the turn timer has expired.
	if state.TurnTimer > 0 && state.TurnStartedAt > 0 {
		if time.Now().Unix()-state.TurnStartedAt >= int64(state.TurnTimer) {
			return fmt.Errorf("turn time expired")
		}
	}
	return nil
}

// ApplyMove returns a new MatchState with the move applied (immutable update).
func ApplyMove(state *MatchState, pos int) *MatchState {
	next := *state // shallow copy — board array is copied by value
	next.Board[pos] = state.Turn
	next.Turn = NextTurn(state.Turn)
	return &next
}

// CheckWinner returns the mark ("X" or "O") that has won, or "" if no winner.
func CheckWinner(board [BoardSize]string) string {
	for _, line := range winLines {
		a, b, c := board[line[0]], board[line[1]], board[line[2]]
		if a != MarkEmpty && a == b && b == c {
			return a
		}
	}
	return MarkEmpty
}

// CheckDraw returns true when the board is full and there is no winner.
func CheckDraw(board [BoardSize]string) bool {
	for _, cell := range board {
		if cell == MarkEmpty {
			return false
		}
	}
	return true
}

// GetGameResult checks for a terminal state after a move.
// Returns ("win", winnerMark), ("draw", ""), or ("", "") if game continues.
func GetGameResult(board [BoardSize]string) (result string, winnerMark string) {
	if w := CheckWinner(board); w != MarkEmpty {
		return ResultWin, w
	}
	if CheckDraw(board) {
		return ResultDraw, MarkEmpty
	}
	return "", MarkEmpty
}

// NextTurn returns the opposing mark.
func NextTurn(current string) string {
	if current == MarkX {
		return MarkO
	}
	return MarkX
}

// MarkToUserID maps a winning mark back to the user ID that holds it.
func MarkToUserID(state *MatchState, mark string) string {
	switch mark {
	case MarkX:
		return state.PlayerX
	case MarkO:
		return state.PlayerO
	default:
		return ""
	}
}

// playerMark returns the mark assigned to a userID in this match.
func playerMark(state *MatchState, userID string) string {
	switch userID {
	case state.PlayerX:
		return MarkX
	case state.PlayerO:
		return MarkO
	default:
		return MarkEmpty
	}
}
