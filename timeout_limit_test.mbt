///|
fn limited(sql : String, maximum : Int32) -> @migration_lens.Report {
  @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=maximum,
  )
}

///|
test "maximum policy is inclusive and enables finite timeout checks" {
  let index = "CREATE INDEX CONCURRENTLY a ON t (id);"
  for value in ["2000", "'2000ms'", "'2s'"] {
    let sql = "SET lock_timeout=" + value + "; " + index
    assert_eq(limited(sql, 2000).exit_code(), 0)
    let over = limited(sql, 1999)
    assert_true(over.complete)
    assert_eq(over.diagnostics[0].code, "ML205")
    assert_true(over.diagnostics[0].message.contains("2000ms"))
    assert_eq(over.source, sql)
    assert_eq(
      over.to_json().stringify(),
      limited(sql, 1999).to_json().stringify(),
    )
    assert_eq(
      @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
      0,
    )
  }
  assert_eq(limited(index, 2000).diagnostics[0].code, "ML202")
  assert_eq(
    limited("SET lock_timeout=0; " + index, 2000).diagnostics[0].code,
    "ML201",
  )
  assert_eq(
    limited("SET lock_timeout=2147483647; " + index, 2147483647).exit_code(),
    0,
  )
  assert_eq(limited("SET lock_timeout=1; " + index, 1).exit_code(), 0)
}

///|
test "limit follows numeric session and local values through rollback and chain" {
  let report = limited(
    "SET lock_timeout='10s'; BEGIN; SET LOCAL lock_timeout='1s'; SAVEPOINT a; SET LOCAL lock_timeout='20s'; ROLLBACK TO a; CREATE INDEX a ON t (id); COMMIT AND CHAIN; COMMIT; CREATE INDEX CONCURRENTLY b ON t (id);",
    2000,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.length(), 2)
  assert_eq(report.diagnostics[0].code, "ML100")
  assert_eq(report.diagnostics[1].code, "ML205")
  assert_true(report.diagnostics[1].message.contains("10000ms"))
  let rollback = limited(
    "SET lock_timeout=100; BEGIN; SET lock_timeout=3000; ROLLBACK; DROP INDEX CONCURRENTLY a;",
    1000,
  )
  assert_eq(rollback.exit_code(), 0)
}

///|
test "invalid policy cannot look clean and subsequent calls recover" {
  for maximum in [0, -1, -2147483648] {
    let sql = "DROP INDEX CONCURRENTLY a;"
    let report = limited(sql, maximum)
    assert_eq(report.exit_code(), 2)
    assert_eq(report.statements, 0)
    assert_eq(report.diagnostics[0].code, "ML011")
    assert_eq(report.source, sql)
  }
  assert_eq(
    limited("SET lock_timeout=1; DROP INDEX CONCURRENTLY a;", 1).exit_code(),
    0,
  )
  assert_eq(
    limited("SET lock_timeout='2147483648ms'; DROP INDEX CONCURRENTLY a;", 2000).exit_code(),
    2,
  )
  assert_eq(
    limited("SET lock_timeout=100; SELECT 1; DROP INDEX CONCURRENTLY a;", 2000).exit_code(),
    2,
  )
}
