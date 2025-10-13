package pghint

import (
	"strings"

	"github.com/aarondl/sqlboiler/v4/queries/qm"
)

// Scan Method Hints
// These hints control which scan method the planner uses for a table.

// SeqScan forces a sequential scan on the specified table.
//
// Example:
//
//	pghint.SeqScan("users")
//	// Generates: /*+ SeqScan(users) */
func SeqScan(table string) qm.QueryMod {
	return qm.WithOptimizerHint("SeqScan(%s)", table)
}

// TidScan forces a TID scan on the specified table.
// This is only effective when ctid is specified in the search condition.
//
// Example:
//
//	pghint.TidScan("users")
//	// Generates: /*+ TidScan(users) */
func TidScan(table string) qm.QueryMod {
	return qm.WithOptimizerHint("TidScan(%s)", table)
}

// IndexScan forces an index scan on the specified table.
// If indexes are specified, only those indexes will be used.
//
// Example:
//
//	pghint.IndexScan("users")                              // Any index
//	pghint.IndexScan("users", "idx_email")                 // Specific index
//	pghint.IndexScan("users", "idx_email", "idx_username") // Multiple indexes
//	// Generates: /*+ IndexScan(users idx_email idx_username) */
func IndexScan(table string, indexes ...string) qm.QueryMod {
	if len(indexes) == 0 {
		return qm.WithOptimizerHint("IndexScan(%s)", table)
	}
	return qm.WithOptimizerHint("IndexScan(%s %s)", table, strings.Join(indexes, " "))
}

// IndexOnlyScan forces an index-only scan on the specified table.
// If indexes are specified, only those indexes will be used.
// If an index-only scan is not available, an index scan may be used instead.
//
// Example:
//
//	pghint.IndexOnlyScan("users", "idx_email")
//	// Generates: /*+ IndexOnlyScan(users idx_email) */
func IndexOnlyScan(table string, indexes ...string) qm.QueryMod {
	if len(indexes) == 0 {
		return qm.WithOptimizerHint("IndexOnlyScan(%s)", table)
	}
	return qm.WithOptimizerHint("IndexOnlyScan(%s %s)", table, strings.Join(indexes, " "))
}

// BitmapScan forces a bitmap scan on the specified table.
// If indexes are specified, only those indexes will be used.
//
// Example:
//
//	pghint.BitmapScan("users", "idx_status", "idx_created_at")
//	// Generates: /*+ BitmapScan(users idx_status idx_created_at) */
func BitmapScan(table string, indexes ...string) qm.QueryMod {
	if len(indexes) == 0 {
		return qm.WithOptimizerHint("BitmapScan(%s)", table)
	}
	return qm.WithOptimizerHint("BitmapScan(%s %s)", table, strings.Join(indexes, " "))
}

// Negative Scan Method Hints
// These hints prevent the planner from using specific scan methods.

// NoSeqScan prevents a sequential scan on the specified table.
//
// Example:
//
//	pghint.NoSeqScan("users")
//	// Generates: /*+ NoSeqScan(users) */
func NoSeqScan(table string) qm.QueryMod {
	return qm.WithOptimizerHint("NoSeqScan(%s)", table)
}

// NoTidScan prevents a TID scan on the specified table.
//
// Example:
//
//	pghint.NoTidScan("users")
//	// Generates: /*+ NoTidScan(users) */
func NoTidScan(table string) qm.QueryMod {
	return qm.WithOptimizerHint("NoTidScan(%s)", table)
}

// NoIndexScan prevents index scans and index-only scans on the specified table.
//
// Example:
//
//	pghint.NoIndexScan("users")
//	// Generates: /*+ NoIndexScan(users) */
func NoIndexScan(table string) qm.QueryMod {
	return qm.WithOptimizerHint("NoIndexScan(%s)", table)
}

// NoIndexOnlyScan prevents index-only scans on the specified table.
//
// Example:
//
//	pghint.NoIndexOnlyScan("users")
//	// Generates: /*+ NoIndexOnlyScan(users) */
func NoIndexOnlyScan(table string) qm.QueryMod {
	return qm.WithOptimizerHint("NoIndexOnlyScan(%s)", table)
}

// NoBitmapScan prevents bitmap scans on the specified table.
//
// Example:
//
//	pghint.NoBitmapScan("users")
//	// Generates: /*+ NoBitmapScan(users) */
func NoBitmapScan(table string) qm.QueryMod {
	return qm.WithOptimizerHint("NoBitmapScan(%s)", table)
}
