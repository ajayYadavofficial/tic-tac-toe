package game

import "testing"

// helper: build a board from a 9-char string, '.' = empty
func boardFrom(s string) [BoardSize]string {
	var b [BoardSize]string
	for i, ch := range s {
		switch ch {
		case 'X':
			b[i] = MarkX
		case 'O':
			b[i] = MarkO
		default:
			b[i] = MarkEmpty
		}
	}
	return b
}

func TestCheckWinner(t *testing.T) {
	tests := []struct {
		name  string
		board string
		want  string
	}{
		{"top row X", "XXX......", MarkX},
		{"mid row X", "...XXX...", MarkX},
		{"bot row X", "......XXX", MarkX},
		{"left col O", "O..O..O..", MarkO},
		{"mid col O", ".O..O..O.", MarkO},
		{"right col O", "..O..O..O", MarkO},
		{"diag X", "X...X...X", MarkX},
		{"anti-diag O", "..O.O.O..", MarkO},
		{"no winner", "XOX......", MarkEmpty},
		{"empty board", ".........", MarkEmpty},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CheckWinner(boardFrom(tt.board))
			if got != tt.want {
				t.Errorf("CheckWinner(%q) = %q, want %q", tt.board, got, tt.want)
			}
		})
	}
}

func TestCheckDraw(t *testing.T) {
	tests := []struct {
		name  string
		board string
		want  bool
	}{
		{"full no winner", "XOXOXOOXO", true},
		{"not full", "XOX......", false},
		{"empty", ".........", false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := CheckDraw(boardFrom(tt.board))
			if got != tt.want {
				t.Errorf("CheckDraw(%q) = %v, want %v", tt.board, got, tt.want)
			}
		})
	}
}

func TestGetGameResult(t *testing.T) {
	tests := []struct {
		name       string
		board      string
		wantResult string
		wantMark   string
	}{
		{"X wins", "XXX......", ResultWin, MarkX},
		{"O wins col", "O..O..O..", ResultWin, MarkO},
		{"draw", "XOXOXOOXO", ResultDraw, MarkEmpty},
		{"ongoing", "XO.......", "", MarkEmpty},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r, m := GetGameResult(boardFrom(tt.board))
			if r != tt.wantResult || m != tt.wantMark {
				t.Errorf("GetGameResult(%q) = (%q, %q), want (%q, %q)",
					tt.board, r, m, tt.wantResult, tt.wantMark)
			}
		})
	}
}

func TestNextTurn(t *testing.T) {
	if NextTurn(MarkX) != MarkO {
		t.Error("NextTurn(X) should be O")
	}
	if NextTurn(MarkO) != MarkX {
		t.Error("NextTurn(O) should be X")
	}
}

func TestValidateMove(t *testing.T) {
	base := &MatchState{
		Board:   boardFrom("........."),
		PlayerX: "uid-x",
		PlayerO: "uid-o",
		Turn:    MarkX,
		Status:  StatusPlaying,
	}

	t.Run("valid move", func(t *testing.T) {
		if err := ValidateMove(base, "uid-x", 0); err != nil {
			t.Errorf("unexpected error: %v", err)
		}
	})

	t.Run("out of range", func(t *testing.T) {
		if err := ValidateMove(base, "uid-x", 9); err == nil {
			t.Error("expected error for position 9")
		}
	})

	t.Run("cell occupied", func(t *testing.T) {
		s := *base
		s.Board[0] = MarkX
		if err := ValidateMove(&s, "uid-x", 0); err == nil {
			t.Error("expected error for occupied cell")
		}
	})

	t.Run("wrong turn", func(t *testing.T) {
		if err := ValidateMove(base, "uid-o", 0); err == nil {
			t.Error("expected error for wrong turn")
		}
	})

	t.Run("not a player", func(t *testing.T) {
		if err := ValidateMove(base, "uid-stranger", 0); err == nil {
			t.Error("expected error for non-player")
		}
	})

	t.Run("game not started", func(t *testing.T) {
		s := *base
		s.Status = StatusWaiting
		if err := ValidateMove(&s, "uid-x", 0); err == nil {
			t.Error("expected error when game not in progress")
		}
	})
}

func TestApplyMove(t *testing.T) {
	state := &MatchState{
		Board:   boardFrom("........."),
		PlayerX: "uid-x",
		PlayerO: "uid-o",
		Turn:    MarkX,
		Status:  StatusPlaying,
	}

	next := ApplyMove(state, 4)

	// Original must be unchanged (immutability)
	if state.Board[4] != MarkEmpty {
		t.Error("ApplyMove mutated original state")
	}
	if next.Board[4] != MarkX {
		t.Errorf("ApplyMove: board[4] = %q, want %q", next.Board[4], MarkX)
	}
	if next.Turn != MarkO {
		t.Errorf("ApplyMove: turn = %q, want %q", next.Turn, MarkO)
	}
}
