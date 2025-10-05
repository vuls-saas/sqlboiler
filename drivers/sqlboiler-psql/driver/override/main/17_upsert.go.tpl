{{- if or (not .Table.IsView) .Table.ViewCapabilities.CanUpsert -}}
{{- $alias := .Aliases.Table .Table.Name}}
{{- $schemaTable := .Table.Name | .SchemaTable}}

{{ if .AddStrictUpsert }}

// UpsertWithPartialIndex attempts an insert using an executor, and does an update or ignore on conflict with partial index support.
// This method automatically filters NULL-valued columns from the conflict clause and adds appropriate WHERE conditions.
// See boil.Columns documentation for how to properly use updateColumns and insertColumns.
func (o *{{$alias.UpSingular}}) UpsertWithPartialIndex({{if .NoContext}}exec boil.Executor{{else}}ctx context.Context, exec boil.ContextExecutor{{end}}, updateOnConflict bool, conflictColumns []string, updateColumns, insertColumns boil.Columns, opts ...UpsertOptionFunc) error {
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

	// Build partial index WHERE clause and filter conflict columns based on NULL values
	var partialIndexWhere string
	var filteredConflict []string
	if len(conflictColumns) > 0 {
		value := reflect.Indirect(reflect.ValueOf(o))
		whereConditions := make([]string, 0, len(conflictColumns))
		filteredConflict = make([]string, 0, len(conflictColumns))

		for _, col := range conflictColumns {
			field := value.FieldByName(strmangle.TitleCase(col))
			if field.IsValid() && field.Kind() == reflect.Struct {
				// Check if it's a null.Type (has Valid field)
				validField := field.FieldByName("Valid")
				if validField.IsValid() && validField.Kind() == reflect.Bool {
					if validField.Bool() {
						// NOT NULL: include in conflict columns and WHERE clause
						filteredConflict = append(filteredConflict, col)
						whereConditions = append(whereConditions, fmt.Sprintf("%s IS NOT NULL", strmangle.IdentQuote(dialect.LQ, dialect.RQ, col)))
					} else {
						// NULL: exclude from conflict columns but add to WHERE clause
						whereConditions = append(whereConditions, fmt.Sprintf("%s IS NULL", strmangle.IdentQuote(dialect.LQ, dialect.RQ, col)))
					}
				} else {
					// Not a null.Type, include in conflict columns
					filteredConflict = append(filteredConflict, col)
				}
			} else {
				// Not a struct field, include in conflict columns
				filteredConflict = append(filteredConflict, col)
			}
		}
		if len(whereConditions) > 0 {
			partialIndexWhere = " WHERE " + strings.Join(whereConditions, " AND ")
		}
	} else {
		filteredConflict = conflictColumns
	}

	// Build cache key in-line uglily - mysql vs psql problems
	buf := strmangle.GetBuffer()
	if updateOnConflict {
		buf.WriteByte('t')
	} else {
		buf.WriteByte('f')
	}
	buf.WriteByte('.')
	for _, c := range filteredConflict {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	buf.WriteString(partialIndexWhere)
	buf.WriteByte('.')
	buf.WriteString(strconv.Itoa(updateColumns.Kind))
	for _, c := range updateColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	buf.WriteString(strconv.Itoa(insertColumns.Kind))
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

		if updateOnConflict && len(update) == 0 {
			return errors.New("{{.PkgName}}: unable to upsert {{.Table.Name}}, could not build update column list")
		}

		ret := strmangle.SetComplement({{$alias.DownSingular}}AllColumns, strmangle.SetIntersect(insert, update))

		conflict := conflictColumns
		if len(conflict) == 0 && updateOnConflict && len(update) != 0 {
			if len({{$alias.DownSingular}}PrimaryKeyColumns) == 0 {
				return errors.New("{{.PkgName}}: unable to upsert {{.Table.Name}}, could not build conflict column list")
			}

			conflict = make([]string, len({{$alias.DownSingular}}PrimaryKeyColumns))
			copy(conflict, {{$alias.DownSingular}}PrimaryKeyColumns)
		}

		// Build conflict target with partial index support
		var conflictTarget string
		if len(filteredConflict) > 0 {
			quotedConflict := strmangle.IdentQuoteSlice(dialect.LQ, dialect.RQ, filteredConflict)
			conflictTarget = "(" + strings.Join(quotedConflict, ", ") + ")" + partialIndexWhere
		}

		// Add conflict target as option
		upsertOpts := append(opts, UpsertConflictTarget(conflictTarget))

		cache.query = buildUpsertQueryPostgres(dialect, "{{$schemaTable}}", updateOnConflict, ret, update, filteredConflict, insert, upsertOpts...)

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
	var returns []any
	if len(cache.retMapping) != 0 {
		returns = queries.PtrsFromMapping(value, cache.retMapping)
	}

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

	if len(cache.retMapping) != 0 {
		{{if .NoContext -}}
		err = exec.QueryRow(cache.query, vals...).Scan(returns...)
		{{else -}}
		err = exec.QueryRowContext(ctx, cache.query, vals...).Scan(returns...)
		{{end -}}
		if errors.Is(err, sql.ErrNoRows) {
			err = nil // Postgres doesn't return anything when there's no update
		}
	} else {
		{{if .NoContext -}}
		_, err = exec.Exec(cache.query, vals...)
		{{else -}}
		_, err = exec.ExecContext(ctx, cache.query, vals...)
		{{end -}}
	}
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
	buf.WriteString(strconv.Itoa(updateColumns.Kind))
	for _, c := range updateColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	buf.WriteString(strconv.Itoa(insertColumns.Kind))
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
	buf.WriteString(strconv.Itoa(updateColumns.Kind))
	for _, c := range updateColumns.Cols {
		buf.WriteString(c)
	}
	buf.WriteByte('.')
	buf.WriteString(strconv.Itoa(insertColumns.Kind))
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
	buf.WriteString(strconv.Itoa(insertColumns.Kind))
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
		insert, ret := insertColumns.InsertColumnSet(
			{{$alias.DownSingular}}AllColumns,
			{{$alias.DownSingular}}ColumnsWithDefault,
			{{$alias.DownSingular}}ColumnsWithoutDefault,
			nzDefaults,
		)

		cache.query = buildUpsertQueryPostgres(dialect, "{{$schemaTable}}", false, ret, nil, nil, insert)

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

	if len(cache.retMapping) != 0 {
		{{if .NoContext -}}
		err = exec.QueryRow(cache.query, vals...).Scan(returns...)
		{{else -}}
		err = exec.QueryRowContext(ctx, cache.query, vals...).Scan(returns...)
		{{end -}}
    if errors.Is(err, sql.ErrNoRows) {
			err = nil // Postgres doesn't return anything when there's no update
		}
	} else {
		{{if .NoContext -}}
		_, err = exec.Exec(cache.query, vals...)
		{{else -}}
		_, err = exec.ExecContext(ctx, cache.query, vals...)
		{{end -}}
	}
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
