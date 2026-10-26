///|
test "RELEASE preserves a session timeout change through COMMIT" {
  let report = @migration_lens.review_sql(
    "SET lock_timeout=100; BEGIN; SAVEPOINT budget; SET SESSION lock_timeout=0; RELEASE SAVEPOINT budget; COMMIT; CREATE INDEX CONCURRENTLY idx ON events(id);",
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML201"])
}

///|
test "RELEASE preserves local overrides but COMMIT still clears them" {
  let sql = "SET lock_timeout=100; BEGIN; SAVEPOINT budget; SET LOCAL lock_timeout=0; RELEASE budget; CREATE INDEX idx ON events(id); COMMIT; DROP INDEX CONCURRENTLY old_idx;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML201", "ML100"])
  assert_eq(
    @migration_lens.Report::parse_json(report.to_json().stringify()),
    Ok(report),
  )
  assert_eq(
    report.to_json(),
    @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      max_lock_timeout_ms=100,
    ).to_json(),
  )
}

///|
test "RELEASE retains disabled finite excessive and unknown values in both scopes" {
  for scope in ["SESSION", "LOCAL"] {
    for
      (value, code) in [
        ("0", "ML201"),
        ("50", ""),
        ("100", ""),
        ("101", "ML205"),
        ("DEFAULT", "ML202"),
      ] {
      let sql = "SET lock_timeout=100; BEGIN; SAVEPOINT parent_point; SAVEPOINT child_point; SET " +
        scope +
        " lock_timeout=" +
        value +
        "; RELEASE parent_point; ANALYZE events; COMMIT; DROP INDEX CONCURRENTLY a;"
      let report = @migration_lens.review_sql(
        sql,
        execution=SeparateStatements,
        max_lock_timeout_ms=100,
      )
      assert_true(report.complete, msg=sql)
      let expected = if code == "" {
        ["ML140"]
      } else if scope == "LOCAL" {
        [code, "ML140"]
      } else {
        [code, "ML140", code]
      }
      assert_eq(report.diagnostics.map(d => d.code), expected, msg=sql)
    }
  }
}

///|
test "releasing an inner savepoint keeps changes until outer rollback" {
  let sql = "SET lock_timeout=100; BEGIN; SAVEPOINT parent_point; SET lock_timeout=101; SAVEPOINT child_point; SET LOCAL lock_timeout=0; RELEASE child_point; ANALYZE events; ROLLBACK TO parent_point; ANALYZE events; COMMIT; DROP INDEX CONCURRENTLY a;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML201", "ML140", "ML140"])
}
