///|
test "concurrent index context and ordinary index findings" {
  let sql = "CREATE INDEX CONCURRENTLY idx ON events (id);"
  let good = @migration_lens.review_sql(sql, execution=SeparateStatements)
  assert_eq(good.exit_code(), 0)
  let bad = @migration_lens.review_sql(sql, execution=ExistingTransaction)
  assert_eq(bad.exit_code(), 1)
  assert_eq(bad.diagnostics[0].code, "ML101")
  assert_eq(
    @migration_lens.review_sql("DROP INDEX idx;", execution=SeparateStatements).diagnostics[0].code,
    "ML100",
  )
  assert_eq(@migration_lens.review_sql(sql, execution=Unknown).exit_code(), 2)
}

///|
test "source preservation and deterministic JSON" {
  let sql = "-- 😀\r\nCREATE /* a /* nested */ b */ INDEX \"x;y\" ON t (id);"
  let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
  assert_true(report.complete)
  assert_eq(report.source, sql)
  assert_eq(report.diagnostics[0].span.start, 7)
  assert_eq(report.diagnostics[0].span.end, sql.length())
  assert_eq(
    report.to_json().stringify(),
    @migration_lens.review_sql(sql, execution=SeparateStatements)
    .to_json()
    .stringify(),
  )
  assert_true(report.to_text().contains("2:1"))
}

///|
test "uncovered input is never a pass and later statements are retained" {
  for
    sql in [
      "SELECT 1;", "CREATE INDEX", "/* open", "SELECT 'open", "DO $$ BEGIN; END $$;",
      "SELECT E'\\';",
    ] {
    assert_eq(
      @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
      2,
    )
  }
  let report = @migration_lens.review_sql(
    "SELECT 1; DROP INDEX idx;",
    execution=SeparateStatements,
  )
  assert_eq(report.statements, 2)
  assert_true(report.diagnostics.any(d => d.code == "ML100"))
  assert_eq(
    @migration_lens.review_sql(
      "-- comment\n; /* empty */",
      execution=SeparateStatements,
    ).exit_code(),
    0,
  )
}
