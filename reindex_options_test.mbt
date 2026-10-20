///|
test "REINDEX option booleans change concurrent transaction behavior" {
  for value in ["", " TRUE", " ON", " 1"] {
    let sql = "REINDEX (CONCURRENTLY" +
      value +
      ", VERBOSE OFF) INDEX public.idx;"
    assert_eq(
      @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
      0,
    )
    assert_eq(
      @migration_lens.review_sql(sql, execution=ExistingTransaction).diagnostics[0].code,
      "ML101",
    )
  }
  for value in ["FALSE", "OFF", "0"] {
    let report = @migration_lens.review_sql(
      "REINDEX (CONCURRENTLY " + value + ", VERBOSE) INDEX idx;",
      execution=SeparateStatements,
    )
    assert_true(report.complete)
    assert_eq(report.diagnostics[0].code, "ML100")
  }
  assert_eq(
    @migration_lens.review_sql(
      "REINDEX (VERBOSE FALSE) INDEX CONCURRENTLY idx;",
      execution=SeparateStatements,
    ).exit_code(),
    0,
  )
}

///|
test "REINDEX tablespace options retain storage risk timeout and source" {
  let sql = "SET lock_timeout=100; REINDEX (TABLESPACE \"fast;space\", CONCURRENTLY ON, VERBOSE 1) INDEX \"schema\".\"index\";"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.length(), 1)
  assert_eq(report.diagnostics[0].code, "ML111")
  assert_eq(report.source, sql)
  assert_eq(
    report.to_json().stringify(),
    @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      max_lock_timeout_ms=100,
    )
    .to_json()
    .stringify(),
  )
}

///|
test "REINDEX rejects duplicate ambiguous malformed and unknown options" {
  for
    sql in [
      "REINDEX () INDEX a;", "REINDEX (VERBOSE,) INDEX a;", "REINDEX (VERBOSE VERBOSE) INDEX a;",
      "REINDEX (CONCURRENTLY TRUE, CONCURRENTLY FALSE) INDEX a;", "REINDEX (CONCURRENTLY FALSE) INDEX CONCURRENTLY a;",
      "REINDEX (VERBOSE 'true') INDEX a;", "REINDEX (VERBOSE 2) INDEX a;", "REINDEX (TABLESPACE) INDEX a;",
      "REINDEX (TABLESPACE s.t) INDEX a;", "REINDEX (VERBOSE, UNKNOWN) INDEX a;",
      "REINDEX (CONCURRENTLY) TABLE t;", "REINDEX (VERBOSE INDEX a;", "REINDEX (CONCURRENTLY) INDEX a unexpected;",
    ] {
    let report = @migration_lens.review_sql(
      sql + " DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_eq(report.diagnostics[0].code, "ML003")
    assert_eq(report.diagnostics[1].code, "ML102")
  }
}
