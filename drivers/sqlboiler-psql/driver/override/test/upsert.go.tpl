{{- $alias := .Aliases.Table .Table.Name}}

{{ if and .AddStrictUpsert .Table.HasPartialIndex }}
{{- range $index := .Table.PartialIndexes }}
{{- if $index.IsUnique }}
func test{{$alias.UpPlural}}UpsertBy{{$index.TitleCase}}(t *testing.T) {
	t.Parallel()

	if len({{$alias.DownSingular}}AllColumns) == len({{$alias.DownSingular}}PrimaryKeyColumns) {
		t.Skip("Skipping table with only primary key columns")
	}

	seed := randomize.NewSeed()
	var err error
	// Attempt the INSERT side of an UPSERT
	o := {{$alias.UpSingular}}{}
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, true); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	{{if $.NoContext -}}
	tx := MustTx(boil.Begin())
	{{else -}}
	ctx := context.Background()
	tx := MustTx(boil.BeginTx(ctx, nil))
	{{- end}}
	defer func() { _ = tx.Rollback() }()
	if err = o.UpsertBy{{$index.TitleCase}}({{if not $.NoContext}}ctx, {{end -}} tx, false, nil, boil.Infer(), boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}} via {{$index.Name}}: %s", err)
	}

	count, err := {{$alias.UpPlural}}().Count({{if not $.NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}

	// Attempt the UPDATE side of an UPSERT
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, false, {{$alias.DownSingular}}PrimaryKeyColumns...); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	if err = o.UpsertBy{{$index.TitleCase}}({{if not $.NoContext}}ctx, {{end -}} tx, true, nil, boil.Infer(), boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}} via {{$index.Name}}: %s", err)
	}

	count, err = {{$alias.UpPlural}}().Count({{if not $.NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}
}
{{- end }}
{{- end }}

func test{{$alias.UpPlural}}UpsertBy{{.Table.PKey.TitleCase}}(t *testing.T) {
	t.Parallel()

	if len({{$alias.DownSingular}}AllColumns) == len({{$alias.DownSingular}}PrimaryKeyColumns) {
		t.Skip("Skipping table with only primary key columns")
	}

	seed := randomize.NewSeed()
	var err error
	// Attempt the INSERT side of an UPSERT
	o := {{$alias.UpSingular}}{}
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, false); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	{{if not $.NoContext}}ctx := context.Background(){{end}}
	tx := MustTx({{if $.NoContext}}{{if $.NoContext}}boil.Begin(){{else}}boil.BeginTx(ctx, nil){{end}}{{else}}boil.BeginTx(ctx, nil){{end}})
	defer func() { _ = tx.Rollback() }()
	if err = o.UpsertBy{{.Table.PKey.TitleCase}}({{if not $.NoContext}}ctx, {{end -}} tx, boil.Infer(), boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}}: %s", err)
	}

	count, err := {{$alias.UpPlural}}().Count({{if not $.NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}

	// Attempt the UPDATE side of an UPSERT
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, true, {{$alias.DownSingular}}PrimaryKeyColumns...); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	if err = o.UpsertBy{{.Table.PKey.TitleCase}}({{if not $.NoContext}}ctx, {{end -}} tx, boil.Infer(), boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}}: %s", err)
	}

	count, err = {{$alias.UpPlural}}().Count({{if not $.NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}
}

{{range $ukey := .Table.UKeys -}}
func test{{$alias.UpPlural}}UpsertBy{{$ukey.TitleCase}}(t *testing.T) {
	t.Parallel()

	if len({{$alias.DownSingular}}AllColumns) == len({{$alias.DownSingular}}PrimaryKeyColumns) {
		t.Skip("Skipping table with only primary key columns")
	}

	uniqueColumns := []string{
    {{- range $ukey.Columns -}}
        "{{- . -}}",
    {{- end -}}
    }

	seed := randomize.NewSeed()
	var err error
	// Attempt the INSERT side of an UPSERT
	o := {{$alias.UpSingular}}{}
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, false); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	{{if not $.NoContext}}ctx := context.Background(){{end}}
	tx := MustTx({{if $.NoContext}}{{if $.NoContext}}boil.Begin(){{else}}boil.BeginTx(ctx, nil){{end}}{{else}}boil.BeginTx(ctx, nil){{end}})
	defer func() { _ = tx.Rollback() }()
	if err = o.UpsertBy{{$ukey.TitleCase}}({{if not $.NoContext}}ctx, {{end -}} tx, boil.Infer(), boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}}: %s", err)
	}

	count, err := {{$alias.UpPlural}}().Count({{if not $.NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}

	// Attempt the UPDATE side of an UPSERT
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, false, uniqueColumns...); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	if err = o.UpsertBy{{$ukey.TitleCase}}({{if not $.NoContext}}ctx, {{end -}} tx, boil.Infer(), boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}}: %s", err)
	}

	count, err = {{$alias.UpPlural}}().Count({{if not $.NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}
}
{{end -}}

func test{{$alias.UpPlural}}UpsertDoNothing(t *testing.T) {
	t.Parallel()

	if len({{$alias.DownSingular}}AllColumns) == len({{$alias.DownSingular}}PrimaryKeyColumns) {
		t.Skip("Skipping table with only primary key columns")
	}

	seed := randomize.NewSeed()
	var err error
	// Attempt the INSERT side of an UPSERT
	o := {{$alias.UpSingular}}{}
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, true); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	{{if not $.NoContext}}ctx := context.Background(){{end}}
	tx := MustTx({{if $.NoContext}}{{if $.NoContext}}boil.Begin(){{else}}boil.BeginTx(ctx, nil){{end}}{{else}}boil.BeginTx(ctx, nil){{end}})
	defer func() { _ = tx.Rollback() }()
	if err = o.UpsertDoNothing({{if not $.NoContext}}ctx, {{end -}} tx, boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}}: %s", err)
	}

	count, err := {{$alias.UpPlural}}().Count({{if not $.NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}

	// Attempt the UPDATE side of an UPSERT
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, false, {{$alias.DownSingular}}PrimaryKeyColumns...); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	if err = o.UpsertDoNothing({{if not $.NoContext}}ctx, {{end -}} tx, boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}}: %s", err)
	}

	count, err = {{$alias.UpPlural}}().Count({{if not $.NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}
}

{{ else }}

func test{{$alias.UpPlural}}Upsert(t *testing.T) {
	t.Parallel()

	if len({{$alias.DownSingular}}AllColumns) == len({{$alias.DownSingular}}PrimaryKeyColumns) {
		t.Skip("Skipping table with only primary key columns")
	}

	seed := randomize.NewSeed()
	var err error
	// Attempt the INSERT side of an UPSERT
	o := {{$alias.UpSingular}}{}
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, true); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	{{if not .NoContext}}ctx := context.Background(){{end}}
	tx := MustTx({{if .NoContext}}{{if .NoContext}}boil.Begin(){{else}}boil.BeginTx(ctx, nil){{end}}{{else}}boil.BeginTx(ctx, nil){{end}})
	defer func() { _ = tx.Rollback() }()
	if err = o.Upsert({{if not .NoContext}}ctx, {{end -}} tx, false, nil, boil.Infer(), boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}}: %s", err)
	}

	count, err := {{$alias.UpPlural}}().Count({{if not .NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}

	// Attempt the UPDATE side of an UPSERT
	if err = randomize.Struct(seed, &o, {{$alias.DownSingular}}DBTypes, false, {{$alias.DownSingular}}PrimaryKeyColumns...); err != nil {
		t.Errorf("Unable to randomize {{$alias.UpSingular}} struct: %s", err)
	}

	if err = o.Upsert({{if not .NoContext}}ctx, {{end -}} tx, true, nil, boil.Infer(), boil.Infer()); err != nil {
		t.Errorf("Unable to upsert {{$alias.UpSingular}}: %s", err)
	}

	count, err = {{$alias.UpPlural}}().Count({{if not .NoContext}}ctx, {{end -}} tx)
	if err != nil {
		t.Error(err)
	}
	if count != 1 {
		t.Error("want one record, got:", count)
	}
}
{{end -}}
