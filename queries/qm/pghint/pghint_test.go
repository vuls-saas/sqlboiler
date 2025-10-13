package pghint

import (
	"testing"

	"github.com/aarondl/sqlboiler/v4/queries"
)

func TestScanMethodHints(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		mod      interface{ Apply(*queries.Query) }
		expected string
	}{
		{
			name:     "SeqScan",
			mod:      SeqScan("users"),
			expected: "SeqScan(users)",
		},
		{
			name:     "TidScan",
			mod:      TidScan("users"),
			expected: "TidScan(users)",
		},
		{
			name:     "IndexScan without indexes",
			mod:      IndexScan("users"),
			expected: "IndexScan(users)",
		},
		{
			name:     "IndexScan with one index",
			mod:      IndexScan("users", "idx_email"),
			expected: "IndexScan(users idx_email)",
		},
		{
			name:     "IndexScan with multiple indexes",
			mod:      IndexScan("users", "idx_email", "idx_username"),
			expected: "IndexScan(users idx_email idx_username)",
		},
		{
			name:     "IndexOnlyScan",
			mod:      IndexOnlyScan("users", "idx_email"),
			expected: "IndexOnlyScan(users idx_email)",
		},
		{
			name:     "BitmapScan",
			mod:      BitmapScan("users", "idx_status", "idx_created"),
			expected: "BitmapScan(users idx_status idx_created)",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			q := &queries.Query{}
			tt.mod.Apply(q)

			hints := queries.GetOptimizerHints(q)
			if len(hints) != 1 {
				t.Fatalf("expected 1 hint, got %d", len(hints))
			}

			if hints[0] != tt.expected {
				t.Errorf("expected %q, got %q", tt.expected, hints[0])
			}
		})
	}
}

func TestNegativeScanMethodHints(t *testing.T) {
	t.Parallel()

	tests := []struct {
		name     string
		mod      interface{ Apply(*queries.Query) }
		expected string
	}{
		{
			name:     "NoSeqScan",
			mod:      NoSeqScan("users"),
			expected: "NoSeqScan(users)",
		},
		{
			name:     "NoTidScan",
			mod:      NoTidScan("users"),
			expected: "NoTidScan(users)",
		},
		{
			name:     "NoIndexScan",
			mod:      NoIndexScan("users"),
			expected: "NoIndexScan(users)",
		},
		{
			name:     "NoIndexOnlyScan",
			mod:      NoIndexOnlyScan("users"),
			expected: "NoIndexOnlyScan(users)",
		},
		{
			name:     "NoBitmapScan",
			mod:      NoBitmapScan("users"),
			expected: "NoBitmapScan(users)",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			q := &queries.Query{}
			tt.mod.Apply(q)

			hints := queries.GetOptimizerHints(q)
			if len(hints) != 1 {
				t.Fatalf("expected 1 hint, got %d", len(hints))
			}

			if hints[0] != tt.expected {
				t.Errorf("expected %q, got %q", tt.expected, hints[0])
			}
		})
	}
}

func TestMultipleHints(t *testing.T) {
	t.Parallel()

	q := &queries.Query{}
	SeqScan("users").Apply(q)
	IndexScan("posts", "idx_user_id").Apply(q)

	hints := queries.GetOptimizerHints(q)
	if len(hints) != 2 {
		t.Fatalf("expected 2 hints, got %d", len(hints))
	}

	expected := []string{
		"SeqScan(users)",
		"IndexScan(posts idx_user_id)",
	}

	for i, exp := range expected {
		if hints[i] != exp {
			t.Errorf("hint %d: expected %q, got %q", i, exp, hints[i])
		}
	}
}
