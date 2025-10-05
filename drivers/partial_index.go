package drivers

import "github.com/aarondl/strmangle"

// PartialIndex represents a partial unique index with WHERE conditions
type PartialIndex struct {
	Name        string   `json:"name"`         // Index name
	Columns     []string `json:"columns"`      // Columns in the index
	WhereClause string   `json:"where_clause"` // WHERE condition from the index definition
	IsUnique    bool     `json:"is_unique"`    // Whether this is a unique index
}

// TitleCase creates a Go-friendly method name for this partial index
func (p PartialIndex) TitleCase() string {
	// Convert index name to Go method name format
	// e.g., "users_email_key_partial" -> "UsersEmailKeyPartial"
	return strmangle.TitleCase(p.Name)
}