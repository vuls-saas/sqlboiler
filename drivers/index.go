package drivers

import "github.com/aarondl/strmangle"

// IndexMethod represents the access method used by an index
type IndexMethod string

const (
	// IndexMethodBtree represents a B-tree index (default for most databases)
	IndexMethodBtree IndexMethod = "btree"
	// IndexMethodHash represents a hash index
	IndexMethodHash IndexMethod = "hash"
	// IndexMethodGist represents a GiST (Generalized Search Tree) index
	IndexMethodGist IndexMethod = "gist"
	// IndexMethodSpgist represents an SP-GiST (Space-Partitioned Generalized Search Tree) index
	IndexMethodSpgist IndexMethod = "spgist"
	// IndexMethodGin represents a GIN (Generalized Inverted Index) index
	IndexMethodGin IndexMethod = "gin"
	// IndexMethodBrin represents a BRIN (Block Range Index) index
	IndexMethodBrin IndexMethod = "brin"
)

type Index struct {
	Name     string      `json:"name"`
	Columns  []string    `json:"columns"`
	IsUnique bool        `json:"unique"`
	Method   IndexMethod `json:"method"`
}

// TitleCase creates a Go-friendly method name for this index
func (i Index) TitleCase() string {
	// Convert index name to Go method name format
	// e.g., "users_email_pkey" -> "UsersEmailPkey"
	return strmangle.TitleCase(i.Name)
}
