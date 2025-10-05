func TestUpsert(t *testing.T) {
  {{- range $index, $table := .Tables}}
  {{- if or $table.IsJoinTable $table.IsView -}}
  {{- else -}}
  {{- $alias := $.Aliases.Table $table.Name}}
  {{if and $.AddStrictUpsert $table.HasPartialIndex -}}
  {{- range $index := $table.PartialIndexes }}
  {{- if $index.IsUnique }}
  t.Run("{{$alias.UpPlural}}", test{{$alias.UpPlural}}UpsertBy{{$index.TitleCase}})
  {{- end }}
  {{- end }}
  t.Run("{{$alias.UpPlural}}", test{{$alias.UpPlural}}UpsertBy{{$table.PKey.TitleCase}})
  {{range $ukey := $table.UKeys -}}
  t.Run("{{$alias.UpPlural}}", test{{$alias.UpPlural}}UpsertBy{{$ukey.TitleCase}})
  {{end -}}
  t.Run("{{$alias.UpPlural}}", test{{$alias.UpPlural}}UpsertDoNothing)
  {{- end -}}
  {{end -}}
  {{- end -}}
}
