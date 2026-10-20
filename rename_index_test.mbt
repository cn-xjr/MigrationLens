///|
test "index replacement is covered and rename keeps its distinct lock warning" {
  let sql = "SET lock_timeout='2s'; CREATE INDEX CONCURRENTLY replacement ON t (id); DROP INDEX CONCURRENTLY original; ALTER INDEX replacement RENAME TO original;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.length(), 1)
  assert_eq(report.diagnostics[0].code, "ML110")
  assert_eq(report.source, sql)
  assert_eq(
    report.to_json().stringify(),
    @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      require_lock_timeout=true,
    )
    .to_json()
    .stringify(),
  )
  let batch = @migration_lens.review_sql(sql, execution=SimpleQuery)
  assert_eq(batch.diagnostics.filter(d => d.code == "ML101").length(), 2)
  assert_true(batch.diagnostics.any(d => d.code == "ML110"))
}

///|
test "rename supports qualified quoted names and transaction-local timeout" {
  for name in ["old", "public.old", "\"s;one\".\"i,one\"", "\"中文😀\""] {
    let sql = "BEGIN; SET LOCAL lock_timeout=100; ALTER INDEX IF EXISTS " +
      name +
      " RENAME TO \"new\"\"name\"; COMMIT;"
    let report = @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      max_lock_timeout_ms=100,
    )
    assert_true(report.complete)
    assert_eq(report.diagnostics.length(), 1)
    assert_eq(report.diagnostics[0].code, "ML110")
  }
  let sql = "-- 😀\r\nALTER INDEX old RENAME TO new;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_eq(report.diagnostics[0].code, "ML202")
  assert_eq(report.diagnostics[1].span.start, 7)
  assert_eq(report.diagnostics[1].span.end, sql.length())
}

///|
test "rename never ignores clauses or accepts a qualified target name" {
  for
    sql in [
      "ALTER INDEX a RENAME TO b.c;", "ALTER INDEX a RENAME TO 'b';", "ALTER INDEX a RENAME TO \"\";",
      "ALTER INDEX a RENAME TO b CASCADE;", "ALTER INDEX a SET TABLESPACE s NOWAIT;",
      "ALTER INDEX a ATTACH PARTITION b;", "ALTER INDEX IF a RENAME TO b;", "ALTER INDEX a, b RENAME TO c;",
    ] {
    let report = @migration_lens.review_sql(
      sql + " DROP INDEX CONCURRENTLY c;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_eq(report.diagnostics[0].code, "ML003")
    assert_eq(report.diagnostics[1].code, "ML102")
  }
}
