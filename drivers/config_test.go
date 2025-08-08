package drivers

import (
	"reflect"
	"testing"
)

func TestConfigMustString(t *testing.T) {
	t.Parallel()

	key := "string"
	tests := []struct {
		Config map[string]any
		Value  string
	}{
		{
			Config: map[string]any{key: "str"},
			Value:  "str",
		},
		{
			Config: map[string]any{key: ""},
			Value:  "",
		},
		{
			Config: map[string]any{key: 5},
			Value:  "",
		},
		{
			Config: map[string]any{},
			Value:  "",
		},
	}

	for i, test := range tests {
		var value string
		var paniced any

		func() {
			defer func() {
				if r := recover(); r != nil {
					paniced = r
				}
			}()
			value = Config(test.Config).MustString(key)
		}()

		if len(test.Value) != 0 {
			if paniced != nil {
				t.Error(i, "wanted a value, but panic'd:", paniced)
			} else if value != test.Value {
				t.Error(i, "want:", test.Value, "got:", value)
			}
		} else {
			if paniced == nil {
				t.Error(i, "expected it to panic")
			}
		}
	}
}

func TestConfigMustInt(t *testing.T) {
	t.Parallel()

	key := "integer"
	tests := []struct {
		Config map[string]any
		Value  int
	}{
		{
			Config: map[string]any{key: 5},
			Value:  5,
		},
		{
			Config: map[string]any{key: 5.0},
			Value:  5,
		},
		{
			Config: map[string]any{key: 0},
			Value:  0,
		},
		{
			Config: map[string]any{},
			Value:  0,
		},
	}

	for i, test := range tests {
		var value int
		var paniced any

		func() {
			defer func() {
				if r := recover(); r != nil {
					paniced = r
				}
			}()
			value = Config(test.Config).MustInt(key)
		}()

		if test.Value != 0 {
			if paniced != nil {
				t.Error(i, "wanted a value, but panic'd:", paniced)
			} else if value != test.Value {
				t.Error(i, "want:", test.Value, "got:", value)
			}
		} else {
			if paniced == nil {
				t.Error(i, "expected it to panic")
			}
		}
	}
}

func TestConfigString(t *testing.T) {
	t.Parallel()

	key := "string"
	tests := []struct {
		Config map[string]any
		Value  string
		Ok     bool
	}{
		{
			Config: map[string]any{key: "str"},
			Value:  "str",
			Ok:     true,
		},
		{
			Config: map[string]any{key: ""},
			Value:  "",
			Ok:     false,
		},
		{
			Config: map[string]any{key: 5},
			Value:  "",
			Ok:     false,
		},
		{
			Config: map[string]any{},
			Value:  "",
			Ok:     false,
		},
	}

	for i, test := range tests {
		value, ok := Config(test.Config).String(key)

		if ok != test.Ok {
			t.Error(i, "ok =", ok)
		}
		if value != test.Value {
			t.Error(i, "want:", test.Value, "got:", value)
		}
	}
}

func TestConfigInt(t *testing.T) {
	t.Parallel()

	key := "integer"
	tests := []struct {
		Config map[string]any
		Value  int
		Ok     bool
	}{
		{
			Config: map[string]any{key: 5},
			Value:  5,
			Ok:     true,
		},
		{
			Config: map[string]any{key: 5.0},
			Value:  5,
			Ok:     true,
		},
		{
			Config: map[string]any{key: 0},
			Value:  0,
			Ok:     false,
		},
		{
			Config: map[string]any{},
			Value:  0,
			Ok:     false,
		},
	}

	for i, test := range tests {
		value, ok := Config(test.Config).Int(key)

		if ok != test.Ok {
			t.Error(i, "ok =", ok)
		}
		if value != test.Value {
			t.Error(i, "want:", test.Value, "got:", value)
		}
	}
}

func TestConfigStringSlice(t *testing.T) {
	t.Parallel()

	key := "slice"
	tests := []struct {
		Config map[string]any
		Value  []string
		Ok     bool
	}{
		{
			Config: map[string]any{key: []string{"str"}},
			Value:  []string{"str"},
			Ok:     true,
		},
		{
			Config: map[string]any{key: []any{"str"}},
			Value:  []string{"str"},
			Ok:     true,
		},
		{
			Config: map[string]any{key: []string{}},
			Value:  nil,
			Ok:     false,
		},
		{
			Config: map[string]any{key: 5},
			Value:  nil,
			Ok:     false,
		},
		{
			Config: map[string]any{},
			Value:  nil,
			Ok:     false,
		},
	}

	for i, test := range tests {
		value, ok := Config(test.Config).StringSlice(key)

		if ok != test.Ok {
			t.Error(i, "ok =", ok)
		}
		if !reflect.DeepEqual(value, test.Value) {
			t.Error(i, "want:", test.Value, "got:", value)
		}
	}
}

func TestTablesFromList(t *testing.T) {
	t.Parallel()

	if TablesFromList(nil) != nil {
		t.Error("expected a shortcut to getting nil back")
	}

	if got := TablesFromList([]string{"a.b", "b", "c.d"}); !reflect.DeepEqual(got, []string{"b"}) {
		t.Error("list was wrong:", got)
	}
}

func TestColumnsFromList(t *testing.T) {
	t.Parallel()

	if ColumnsFromList(nil, "table") != nil {
		t.Error("expected a shortcut to getting nil back")
	}

	if got := ColumnsFromList([]string{"a.b", "b", "c.d", "c.a"}, "c"); !reflect.DeepEqual(got, []string{"d", "a"}) {
		t.Error("list was wrong:", got)
	}
	if got := ColumnsFromList([]string{"a.b", "b", "c.d", "c.a"}, "b"); len(got) != 0 {
		t.Error("list was wrong:", got)
	}
	if got := ColumnsFromList([]string{"*.b", "b", "c.d"}, "c"); !reflect.DeepEqual(got, []string{"b", "d"}) {
		t.Error("list was wrong:", got)
	}
}

func TestConfig_MustForeignKeys(t *testing.T) {
	tests := []struct {
		name  string
		c     Config
		want  []ForeignKey
		panic bool
	}{
		{
			name:  "no foreign keys",
			c:     Config{},
			want:  nil,
			panic: false,
		},
		{
			name: "nil foreign keys",
			c: Config{
				"foreign-keys": nil,
			},
			want:  nil,
			panic: false,
		},
		{
			name: "have foreign keys",
			c: Config{
				"foreign-keys": []ForeignKey{
					{
						Name:          "test_fk",
						Table:         "table_name",
						Column:        "column_name",
						ForeignColumn: "foreign_column_name",
						ForeignTable:  "foreign_table_name",
					},
				},
			},
			want: []ForeignKey{
				{
					Name:          "test_fk",
					Table:         "table_name",
					Column:        "column_name",
					ForeignColumn: "foreign_column_name",
					ForeignTable:  "foreign_table_name",
				},
			},
			panic: false,
		},
		{
			name: "invalid foreign keys",
			c: Config{
				"foreign-keys": 1,
			},
			panic: true,
		},
		{
			name: "foreign keys in []any format",
			c: Config{
				"foreign-keys": []any{
					map[string]any{
						"name":           "test_fk",
						"table":          "table_name",
						"column":         "column_name",
						"foreign_column": "foreign_column_name",
						"foreign_table":  "foreign_table_name",
					},
				},
			},
			want: []ForeignKey{
				{
					Name:          "test_fk",
					Table:         "table_name",
					Column:        "column_name",
					ForeignColumn: "foreign_column_name",
					ForeignTable:  "foreign_table_name",
				},
			},
			panic: false,
		},
		{
			name: "invalid foreign keys in []any format",
			c: Config{
				"foreign-keys": []any{
					"123",
				},
			},
			panic: true,
		},
		{
			name: "foreign keys in []map[string]string format but missing fields",
			c: Config{
				"foreign-keys": []any{
					map[string]any{
						"name": "test_fk",
					},
				},
			},
			want:  nil,
			panic: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var got []ForeignKey
			var paniced any
			func() {
				defer func() {
					if r := recover(); r != nil {
						paniced = r
					}
				}()
				got = tt.c.MustForeignKeys(ConfigForeignKeys)
			}()

			if tt.panic && paniced == nil {
				t.Errorf("MustForeignKeys() should have panicked")
			}
			if !tt.panic && paniced != nil {
				t.Errorf("MustForeignKeys() should not have panicked")
			}
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("MustForeignKeys() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestCombineConfigAndDBForeignKeys(t *testing.T) {
	configForeignKeys := []ForeignKey{
		{
			Name:          "config_fk1",
			Table:         "table_A",
			Column:        "column_A1",
			ForeignColumn: "column_B1",
			ForeignTable:  "table_B",
		},
		{
			Name:          "config_fk2",
			Table:         "table_C",
			Column:        "column_C1",
			ForeignColumn: "column_B1",
			ForeignTable:  "table_B",
		},
		{
			Name:          "config_fk3",
			Table:         "table_A",
			Column:        "column_A2",
			ForeignColumn: "column_D2",
			ForeignTable:  "table_D",
		},
	}
	tableName := "table_A"
	dbForeignKeys := []ForeignKey{
		{
			Name:          "db_fk1",
			Table:         "table_A",
			Column:        "column_A1",
			ForeignColumn: "column_E1",
			ForeignTable:  "table_E",
		},
	}

	expected := []ForeignKey{
		configForeignKeys[0],
		configForeignKeys[2],
	}

	got := CombineConfigAndDBForeignKeys(configForeignKeys, tableName, dbForeignKeys)

	if !reflect.DeepEqual(got, expected) {
		t.Errorf("CombineConfigAndDBForeignKeys() = %v, want %v", got, expected)
	}
}