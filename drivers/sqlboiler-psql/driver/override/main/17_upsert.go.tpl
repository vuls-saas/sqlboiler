{{- if or (not .Table.IsView) .Table.ViewCapabilities.CanUpsert -}}
{{- $alias := .Aliases.Table .Table.Name}}
{{- $schemaTable := .Table.Name | .SchemaTable}}

{{ if and .AddStrictUpsert .Table.HasPartialIndex }}

{{- range $index := .Table.PartialIndexes }}
{{- if $index.IsUnique }}

// UpsertBy{{$index.TitleCase}} attempts an insert using an executor, and does an update or ignore on conflict
// with the partial unique index: {{$index.Name}}
// Partial index WHERE clause: {{$index.WhereClause}}
// Index columns: {{join ", " $index.Columns}}
func (o *{{$alias.UpSingular}}) UpsertBy{{$index.TitleCase}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, updateOnConflict bool, updateColumns, insertColumns boil.Columns, opts ...UpsertOptionFunc) error {
	if o == nil {
		return errors.New("{{$.PkgName}}: no {{$.Table.Name}} provided for upsert")
	}

	{{- template "timestamp_upsert_helper" $ }}

	{{if not $.NoHooks -}}
	if err := o.doBeforeUpsertHooks({{if not $.NoContext}}ctx, {{end -}} exec); err != nil {
		return err
	}
	{{- end}}

	nzDefaults := queries.NonZeroDefaultSet({{$alias.DownSingular}}ColumnsWithDefault, o)

	// Use the columns from the partial index
	conflictColumns := []string{
	{{- range $col := $index.Columns }}
		"{{$col}}",
	{{- end }}
	}

	// Build cache key
	buf := strmangle.GetBuffer()
	if updateOnConflict {
		buf.WriteByte('t')
	} else {
		buf.WriteByte('f')
	}
	buf.WriteByte('.')
	buf.WriteString("{{$index.Name}}")
	buf.WriteByte('.')
	buf.WriteString(fmt.Sprint(updateColumns.Kind))
	for _, c := range updateColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	buf.WriteString(fmt.Sprint(insertColumns.Kind))
	for _, c := range insertColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	for _, c := range nzDefaults {
		buf.WriteString(c)
	}
	key := buf.String()
	strmangle.PutBuffer(buf)

	{{$alias.DownSingular}}UpsertCacheMut.RLock()
	cache, cached := {{$alias.DownSingular}}UpsertCache[key]
	{{$alias.DownSingular}}UpsertCacheMut.RUnlock()

	var err error

	if !cached {
		insert, _ := insertColumns.InsertColumnSet(
			{{$alias.DownSingular}}AllColumns,
			{{$alias.DownSingular}}ColumnsWithDefault,
			{{$alias.DownSingular}}ColumnsWithoutDefault,
			nzDefaults,
		)

		update := updateColumns.UpdateColumnSet(
			{{$alias.DownSingular}}AllColumns,
			{{$alias.DownSingular}}PrimaryKeyColumns,
		)
		{{if filterColumnsByAuto true $.Table.Columns }}
		insert = strmangle.SetComplement(insert, {{$alias.DownSingular}}GeneratedColumns)
		update = strmangle.SetComplement(update, {{$alias.DownSingular}}GeneratedColumns)
		{{- end }}

		if updateOnConflict && len(update) == 0 {
			return errors.New("{{$.PkgName}}: unable to upsert {{$.Table.Name}}, could not build update column list")
		}

		ret := strmangle.SetComplement({{$alias.DownSingular}}AllColumns, strmangle.SetIntersect(insert, update))

		// For partial indexes, we need to specify the WHERE clause in the conflict target
		conflictTarget := fmt.Sprintf("(%s) WHERE {{$index.WhereClause}}", strings.Join(strmangle.IdentQuoteSlice(dialect.LQ, dialect.RQ, conflictColumns), ", "))
		allOpts := append([]UpsertOptionFunc{UpsertConflictTarget(conflictTarget)}, opts...)
		cache.query = buildUpsertQueryPostgres(dialect, "{{$schemaTable}}", updateOnConflict, ret, update, nil, insert, allOpts...)
		cache.valueMapping, err = queries.BindMapping({{$alias.DownSingular}}Type, {{$alias.DownSingular}}Mapping, insert)
		if err != nil {
			return err
		}
		if len(ret) != 0 {
			cache.retMapping, err = queries.BindMapping({{$alias.DownSingular}}Type, {{$alias.DownSingular}}Mapping, ret)
			if err != nil {
				return err
			}
		}
	}

	value := reflect.Indirect(reflect.ValueOf(o))
	vals := queries.ValuesFromMapping(value, cache.valueMapping)
	var returns []interface{}
	if len(cache.retMapping) != 0 {
		returns = queries.PtrsFromMapping(value, cache.retMapping)
	}

	{{if $.NoContext -}}
	if boil.DebugMode {
		fmt.Fprintln(boil.DebugWriter, cache.query)
		fmt.Fprintln(boil.DebugWriter, vals)
	}
	{{else -}}
	if boil.IsDebug(ctx) {
		writer := boil.DebugWriterFrom(ctx)
		fmt.Fprintln(writer, cache.query)
		fmt.Fprintln(writer, vals)
	}
	{{end -}}

	if len(cache.retMapping) != 0 {
		{{if $.NoContext -}}
		err = exec.QueryRow(cache.query, vals...).Scan(returns...)
		{{else -}}
		err = exec.QueryRowContext(ctx, cache.query, vals...).Scan(returns...)
		{{end -}}
		if errors.Is(err, sql.ErrNoRows) {
			err = nil // Postgres doesn't return anything when there's no update
		}
	} else {
		{{if $.NoContext -}}
		_, err = exec.Exec(cache.query, vals...)
		{{else -}}
		_, err = exec.ExecContext(ctx, cache.query, vals...)
		{{end -}}
	}
	if err != nil {
		return errors.Wrap(err, "{{$.PkgName}}: unable to upsert {{$.Table.Name}}")
	}

	if !cached {
		{{$alias.DownSingular}}UpsertCacheMut.Lock()
		{{$alias.DownSingular}}UpsertCache[key] = cache
		{{$alias.DownSingular}}UpsertCacheMut.Unlock()
	}

	{{if not $.NoHooks -}}
	return o.doAfterUpsertHooks({{if not $.NoContext}}ctx, {{end -}} exec)
	{{- else -}}
	return nil
	{{- end}}
}
{{- end }}
{{- end }}
{{- end }}

{{ if and .AddStrictUpsert .Table.PKey }}

// UpsertBy{{.Table.PKey.TitleCase}} attempts an insert using an executor, and does an update or ignore on conflict.
// Primary Key is {{.Table.PKey.Columns}}
// See boil.Columns documentation for how to properly use updateColumns and insertColumns.
func (o *{{$alias.UpSingular}}) UpsertBy{{.Table.PKey.TitleCase}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, updateColumns, insertColumns boil.Columns) error {
	if o == nil {
		return errors.New("{{$.PkgName}}: no {{$.Table.Name}} provided for upsert")
	}

	{{- template "timestamp_upsert_helper" $ }}

	{{if not $.NoHooks -}}
	if err := o.doBeforeUpsertHooks({{if not $.NoContext}}ctx, {{end -}} exec); err != nil {
		return err
	}
	{{- end}}

	nzDefaults := queries.NonZeroDefaultSet({{$alias.DownSingular}}ColumnsWithDefault, o)

	// Build cache key in-line uglily - mysql vs psql problems
	buf := strmangle.GetBuffer()
	buf.WriteByte('f')
	buf.WriteByte('.')

    {{range .Table.PKey.Columns -}}
	buf.WriteString("{{.}}")
    {{ end -}}

	buf.WriteByte('.')
	buf.WriteString(fmt.Sprint(updateColumns.Kind))
	for _, c := range updateColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	buf.WriteString(fmt.Sprint(insertColumns.Kind))
	for _, c := range insertColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	for _, c := range nzDefaults {
		buf.WriteString(c)
	}
	key := buf.String()
	strmangle.PutBuffer(buf)

	{{$alias.DownSingular}}UpsertCacheMut.RLock()
	cache, cached := {{$alias.DownSingular}}UpsertCache[key]
	{{$alias.DownSingular}}UpsertCacheMut.RUnlock()

	var err error

	if !cached {
		insert, _ := insertColumns.InsertColumnSet(
			{{$alias.DownSingular}}AllColumns,
			{{$alias.DownSingular}}ColumnsWithDefault,
			{{$alias.DownSingular}}ColumnsWithoutDefault,
			nzDefaults,
		)
		update := updateColumns.UpdateColumnSet(
			{{$alias.DownSingular}}AllColumns,
			{{$alias.DownSingular}}PrimaryKeyColumns,
		)

		{{if filterColumnsByAuto true .Table.Columns }}
		insert = strmangle.SetComplement(insert, {{$alias.DownSingular}}GeneratedColumns)
		update = strmangle.SetComplement(update, {{$alias.DownSingular}}GeneratedColumns)
		{{- end }}

		if len(update) == 0 {
			return errors.New("{{$.PkgName}}: unable to upsert {{$.Table.Name}}, could not build update column list")
		}

		ret := strmangle.SetComplement({{$alias.DownSingular}}AllColumns, strmangle.SetIntersect(insert, update))

		conflict := []string{
		{{ range .Table.PKey.Columns -}}
				"{{.}}",
		{{ end -}}
		}

		if len(conflict) == 0 && len(update) != 0 {
			if len({{$alias.DownSingular}}PrimaryKeyColumns) == 0 {
				return errors.New("{{.PkgName}}: unable to upsert {{.Table.Name}}, could not build conflict column list")
			}

			conflict = make([]string, len({{$alias.DownSingular}}PrimaryKeyColumns))
			copy(conflict, {{$alias.DownSingular}}PrimaryKeyColumns)
		}

		cache.query = buildUpsertQueryPostgres(dialect, "{{$schemaTable}}", true, ret, update, conflict, insert)

		cache.valueMapping, err = queries.BindMapping({{$alias.DownSingular}}Type, {{$alias.DownSingular}}Mapping, insert)
		if err != nil {
			return err
		}
		if len(ret) != 0 {
			cache.retMapping, err = queries.BindMapping({{$alias.DownSingular}}Type, {{$alias.DownSingular}}Mapping, ret)
			if err != nil {
				return err
			}
		}
	}

	value := reflect.Indirect(reflect.ValueOf(o))
	vals := queries.ValuesFromMapping(value, cache.valueMapping)
	var returns []interface{}
	if len(cache.retMapping) != 0 {
		returns = queries.PtrsFromMapping(value, cache.retMapping)
	}

	{{if $.NoContext -}}
	if boil.DebugMode {
		fmt.Fprintln(boil.DebugWriter, cache.query)
		fmt.Fprintln(boil.DebugWriter, vals)
	}
	{{else -}}
	if boil.IsDebug(ctx) {
		writer := boil.DebugWriterFrom(ctx)
		fmt.Fprintln(writer, cache.query)
		fmt.Fprintln(writer, vals)
	}
	{{end -}}

	if len(cache.retMapping) != 0 {
		{{if $.NoContext -}}
		err = exec.QueryRow(cache.query, vals...).Scan(returns...)
		{{else -}}
		err = exec.QueryRowContext(ctx, cache.query, vals...).Scan(returns...)
		{{end -}}
    if errors.Is(err, sql.ErrNoRows) {
			err = nil // Postgres doesn't return anything when there's no update
		}
	} else {
		{{if $.NoContext -}}
		_, err = exec.Exec(cache.query, vals...)
		{{else -}}
		_, err = exec.ExecContext(ctx, cache.query, vals...)
		{{end -}}
	}
	if err != nil {
		return errors.Wrap(err, "{{$.PkgName}}: unable to upsert {{$.Table.Name}}")
	}

	if !cached {
		{{$alias.DownSingular}}UpsertCacheMut.Lock()
		{{$alias.DownSingular}}UpsertCache[key] = cache
		{{$alias.DownSingular}}UpsertCacheMut.Unlock()
	}

	{{if not $.NoHooks -}}
	return o.doAfterUpsertHooks({{if not $.NoContext}}ctx, {{end -}} exec)
	{{- else -}}
	return nil
	{{- end}}
}

{{- range $ukey := .Table.UKeys -}}

// UpsertBy{{$ukey.TitleCase}} attempts an insert using an executor, and does an update or ignore on conflict.
// See boil.Columns documentation for how to properly use updateColumns and insertColumns.
// Unique Key is {{$ukey.Columns}}
func (o *{{$alias.UpSingular}}) UpsertBy{{$ukey.TitleCase}}({{if $.NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, updateColumns, insertColumns boil.Columns) error {
	if o == nil {
		return errors.New("{{$.PkgName}}: no {{$.Table.Name}} provided for upsert")
	}

	{{- template "timestamp_upsert_helper" $ }}

	{{if not $.NoHooks -}}
	if err := o.doBeforeUpsertHooks({{if not $.NoContext}}ctx, {{end -}} exec); err != nil {
		return err
	}
	{{- end}}

	nzDefaults := queries.NonZeroDefaultSet({{$alias.DownSingular}}ColumnsWithDefault, o)

	// Build cache key in-line uglily - mysql vs psql problems
	buf := strmangle.GetBuffer()
	buf.WriteByte('f')
	buf.WriteByte('.')

    {{range $ukey.Columns -}}
	buf.WriteString("{{.}}")
    {{ end -}}

	buf.WriteByte('.')
	buf.WriteString(fmt.Sprint(updateColumns.Kind))
	for _, c := range updateColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	buf.WriteString(fmt.Sprint(insertColumns.Kind))
	for _, c := range insertColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	for _, c := range nzDefaults {
		buf.WriteString(c)
	}
	key := buf.String()
	strmangle.PutBuffer(buf)

	{{$alias.DownSingular}}UpsertCacheMut.RLock()
	cache, cached := {{$alias.DownSingular}}UpsertCache[key]
	{{$alias.DownSingular}}UpsertCacheMut.RUnlock()

	var err error

	if !cached {
		insert, _ := insertColumns.InsertColumnSet(
			{{$alias.DownSingular}}AllColumns,
			{{$alias.DownSingular}}ColumnsWithDefault,
			{{$alias.DownSingular}}ColumnsWithoutDefault,
			nzDefaults,
		)
		update := updateColumns.UpdateColumnSet(
			{{$alias.DownSingular}}AllColumns,
			{{$alias.DownSingular}}PrimaryKeyColumns,
		)

		if len(update) == 0 {
			return errors.New("{{$.PkgName}}: unable to upsert {{$.Table.Name}}, could not build update column list")
		}

		ret := strmangle.SetComplement({{$alias.DownSingular}}AllColumns, strmangle.SetIntersect(insert, update))

        {{if gt (len $ukey.Columns) 0 -}}
		conflict := []string{
        {{ range $ukey.Columns -}}

            "{{.}}",
        {{ end -}}
        }
        {{ else -}}
		conflict := make([]string, len({{$alias.DownSingular}}PrimaryKeyColumns))
		copy(conflict, {{$alias.DownSingular}}PrimaryKeyColumns)
        {{ end -}}

		cache.query = buildUpsertQueryPostgres(dialect, "{{$schemaTable}}", true, ret, update, conflict, insert)

		cache.valueMapping, err = queries.BindMapping({{$alias.DownSingular}}Type, {{$alias.DownSingular}}Mapping, insert)
		if err != nil {
			return err
		}
		if len(ret) != 0 {
			cache.retMapping, err = queries.BindMapping({{$alias.DownSingular}}Type, {{$alias.DownSingular}}Mapping, ret)
			if err != nil {
				return err
			}
		}
	}

	value := reflect.Indirect(reflect.ValueOf(o))
	vals := queries.ValuesFromMapping(value, cache.valueMapping)
	var returns []interface{}
	if len(cache.retMapping) != 0 {
		returns = queries.PtrsFromMapping(value, cache.retMapping)
	}

	{{if $.NoContext -}}
	if boil.DebugMode {
		fmt.Fprintln(boil.DebugWriter, cache.query)
		fmt.Fprintln(boil.DebugWriter, vals)
	}
	{{else -}}
	if boil.IsDebug(ctx) {
		writer := boil.DebugWriterFrom(ctx)
		fmt.Fprintln(writer, cache.query)
		fmt.Fprintln(writer, vals)
	}
	{{end -}}

	if len(cache.retMapping) != 0 {
		{{if $.NoContext -}}
		err = exec.QueryRow(cache.query, vals...).Scan(returns...)
		{{else -}}
		err = exec.QueryRowContext(ctx, cache.query, vals...).Scan(returns...)
		{{end -}}
    if errors.Is(err, sql.ErrNoRows) {
			err = nil // Postgres doesn't return anything when there's no update
		}
	} else {
		{{if $.NoContext -}}
		_, err = exec.Exec(cache.query, vals...)
		{{else -}}
		_, err = exec.ExecContext(ctx, cache.query, vals...)
		{{end -}}
	}
	if err != nil {
		return errors.Wrap(err, "{{$.PkgName}}: unable to upsert {{$.Table.Name}}")
	}

	if !cached {
		{{$alias.DownSingular}}UpsertCacheMut.Lock()
		{{$alias.DownSingular}}UpsertCache[key] = cache
		{{$alias.DownSingular}}UpsertCacheMut.Unlock()
	}

	{{if not $.NoHooks -}}
	return o.doAfterUpsertHooks({{if not $.NoContext}}ctx, {{end -}} exec)
	{{- else -}}
	return nil
	{{- end}}
}

{{end -}}

// UpsertDoNothing attempts an insert using an executor or ignore on conflict.
// See boil.Columns documentation for how to properly use insertColumns.
func (o *{{$alias.UpSingular}}) UpsertDoNothing({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, insertColumns boil.Columns) error {
	if o == nil {
		return errors.New("{{.PkgName}}: no {{.Table.Name}} provided for upsert")
	}

	{{- template "timestamp_upsert_helper" . }}

	{{if not .NoHooks -}}
	if err := o.doBeforeUpsertHooks({{if not .NoContext}}ctx, {{end -}} exec); err != nil {
		return err
	}
	{{- end}}

	nzDefaults := queries.NonZeroDefaultSet({{$alias.DownSingular}}ColumnsWithDefault, o)

	// Build cache key in-line uglily - mysql vs psql problems
	buf := strmangle.GetBuffer()
	buf.WriteByte('f')
	buf.WriteByte('.')
	buf.WriteByte('.')
	buf.WriteByte('.')
	buf.WriteString(fmt.Sprint(insertColumns.Kind))
	for _, c := range insertColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	for _, c := range nzDefaults {
		buf.WriteString(c)
	}
	key := buf.String()
	strmangle.PutBuffer(buf)

	{{$alias.DownSingular}}UpsertCacheMut.RLock()
	cache, cached := {{$alias.DownSingular}}UpsertCache[key]
	{{$alias.DownSingular}}UpsertCacheMut.RUnlock()

	var err error

	if !cached {
		insert, _ := insertColumns.InsertColumnSet(
			{{$alias.DownSingular}}AllColumns,
			{{$alias.DownSingular}}ColumnsWithDefault,
			{{$alias.DownSingular}}ColumnsWithoutDefault,
			nzDefaults,
		)

		cache.query = buildUpsertQueryPostgres(dialect, "{{$schemaTable}}", false, nil, nil, nil, insert)

		cache.valueMapping, err = queries.BindMapping({{$alias.DownSingular}}Type, {{$alias.DownSingular}}Mapping, insert)
		if err != nil {
			return err
		}
	}

	value := reflect.Indirect(reflect.ValueOf(o))
	vals := queries.ValuesFromMapping(value, cache.valueMapping)

	{{if .NoContext -}}
	if boil.DebugMode {
		fmt.Fprintln(boil.DebugWriter, cache.query)
		fmt.Fprintln(boil.DebugWriter, vals)
	}
	{{else -}}
	if boil.IsDebug(ctx) {
		writer := boil.DebugWriterFrom(ctx)
		fmt.Fprintln(writer, cache.query)
		fmt.Fprintln(writer, vals)
	}
	{{end -}}

	{{if .NoContext -}}
	_, err = exec.Exec(cache.query, vals...)
	{{else -}}
	_, err = exec.ExecContext(ctx, cache.query, vals...)
	{{end -}}
	if err != nil {
		return errors.Wrap(err, "{{.PkgName}}: unable to upsert {{.Table.Name}}")
	}

	if !cached {
		{{$alias.DownSingular}}UpsertCacheMut.Lock()
		{{$alias.DownSingular}}UpsertCache[key] = cache
		{{$alias.DownSingular}}UpsertCacheMut.Unlock()
	}

	{{if not .NoHooks -}}
	return o.doAfterUpsertHooks({{if not .NoContext}}ctx, {{end -}} exec)
	{{- else -}}
	return nil
	{{- end}}
}

{{end}}
{{end -}}
