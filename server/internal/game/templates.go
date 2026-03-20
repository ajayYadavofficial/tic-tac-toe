package game

// Template defines a game blueprint shown on the lobby screen.
// TurnSecs = 0 means no timer; >0 means seconds per turn.
type Template struct {
	ID          int    `json:"id"`
	Variant     string `json:"variant"`
	Name        string `json:"name"`
	Description string `json:"description"`
	MinPlayers  int    `json:"min_players"`
	MaxPlayers  int    `json:"max_players"`
	TurnSecs    int    `json:"turn_secs"`
}

// AllTemplates is the authoritative list of available game templates.
var AllTemplates = []Template{
	{
		ID:          1,
		Variant:     GameModeClassic,
		Name:        "Classic",
		Description: "Pure Tic-Tac-Toe. No clock, no pressure.",
		MinPlayers:  MinPlayers,
		MaxPlayers:  MaxPlayers,
		TurnSecs:    0,
	},
	{
		ID:          2,
		Variant:     GameModeBlitz,
		Name:        "Blitz",
		Description: "10 seconds per turn. Think fast!",
		MinPlayers:  MinPlayers,
		MaxPlayers:  MaxPlayers,
		TurnSecs:    BlitzTurnSecs,
	},
}

// TemplateByID returns the template with the given ID, or nil if not found.
func TemplateByID(id int) *Template {
	for i := range AllTemplates {
		if AllTemplates[i].ID == id {
			return &AllTemplates[i]
		}
	}
	return nil
}
