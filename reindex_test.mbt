///|
test "concurrent reindex uses dispatch and initial transaction context" {
  for
    name in [
      "events_idx", "public.events_idx", "\"s;one\".\"i,one\"", "\"中文😀\"",
    ] {
    let sql = "REINDEX INDEX CONCURRENTLY " + name + ";"
    assert_eq(
      @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
      0,
    )
    assert_eq(
      @migration_lens.review_sql(sql, execution=ExistingTransaction).diagnostics[0].code,
      "ML101",
    )
    assert_eq(
      @migration_lens.review_sql(
        sql,
        execution=SimpleQuery,
        initial_transaction=true,
      ).diagnostics[0].code,
      "ML101",
    )
    let batch = @migration_lens.review_sql(
      "SET lock_timeout=100; " + sql,
      execution=SimpleQuery,
    )
    assert_eq(batch.diagnostics[0].code, "ML101")
  }
}

///|
test "ordinary reindex warns about blocking and conditional partition restrictions" {
  let sql = "REINDEX INDEX public.events_idx;"
  let plain = @migration_lens.review_sql(sql, execution=SeparateStatements)
  assert_true(plain.complete)
  assert_eq(plain.diagnostics[0].code, "ML100")
  let tx = @migration_lens.review_sql(
    "BEGIN; " + sql + " COMMIT;",
    execution=SeparateStatements,
  )
  assert_eq(tx.diagnostics[0].code, "ML108")
  assert_eq(tx.diagnostics[1].code, "ML100")
}

///|
test "reindex enforces timeout scopes and retains incomplete context" {
  let report = @migration_lens.review_sql(
    "SET lock_timeout='3s'; REINDEX INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
    max_lock_timeout_ms=2000,
  )
  assert_eq(report.diagnostics[0].code, "ML205")
  let unknown = @migration_lens.review_sql(
    "SELECT 1; REINDEX INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
  )
  assert_eq(unknown.exit_code(), 2)
  assert_eq(unknown.diagnostics[1].code, "ML102")
  assert_eq(unknown.source, "SELECT 1; REINDEX INDEX CONCURRENTLY a;")
}

///|
test "reindex does not discard scopes options or trailing SQL" {
  for
    sql in [
      "REINDEX TABLE t;", "REINDEX DATABASE;", "REINDEX (VERBOSE) INDEX a;", "REINDEX INDEX a, b;",
      "REINDEX INDEX 'a';", "REINDEX INDEX a.b.c;", "REINDEX INDEX CONCURRENTLY;",
      "REINDEX INDEX a CASCADE;", "REINDEX INDEX \"\";",
    ] {
    assert_eq(
      @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
      2,
      msg=sql,
    )
  }
  let sql = "-- 😀\r\nREINDEX /* nested /* comment */ ok */ INDEX CONCURRENTLY \"a\"\"b\";"
  let report = @migration_lens.review_sql(sql, execution=ExistingTransaction)
  assert_eq(report.diagnostics[0].span.start, 7)
  assert_eq(report.diagnostics[0].span.end, sql.length())
  assert_eq(report.source, sql)
  assert_eq(
    report.to_json().stringify(),
    @migration_lens.review_sql(sql, execution=ExistingTransaction)
    .to_json()
    .stringify(),
  )
}
