///|
fn policy(sql : String) -> @migration_lens.Report {
  @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
}

///|
test "timeout policy is opt-in and session timeout survives independent dispatch" {
  let index = "CREATE INDEX CONCURRENTLY a ON t (id);"
  assert_eq(
    @migration_lens.review_sql(index, execution=SeparateStatements).exit_code(),
    0,
  )
  assert_eq(policy(index).diagnostics[0].code, "ML202")
  assert_eq(policy("SET lock_timeout = '3s'; " + index).exit_code(), 0)
  assert_eq(policy("SET SESSION lock_timeout TO 3000; " + index).exit_code(), 0)
  let ignored = policy("SET LOCAL lock_timeout = '3s'; " + index)
  assert_eq(ignored.diagnostics[0].code, "ML200")
  assert_eq(ignored.diagnostics[1].code, "ML202")
}

///|
test "commit preserves session SET but restores local setting" {
  let sql = "SET lock_timeout='2s'; BEGIN; SET LOCAL lock_timeout=0; COMMIT; CREATE INDEX CONCURRENTLY a ON t (id);"
  assert_eq(policy(sql).exit_code(), 0)
  assert_eq(
    policy(
      "BEGIN; SET lock_timeout='2s'; COMMIT; CREATE INDEX CONCURRENTLY a ON t (id);",
    ).exit_code(),
    0,
  )
  assert_eq(
    policy(
      "BEGIN; SET LOCAL lock_timeout='2s'; COMMIT; CREATE INDEX CONCURRENTLY a ON t (id);",
    ).diagnostics[0].code,
    "ML202",
  )
}

///|
test "rollback restores earlier session settings and idle rollback has no effect" {
  assert_eq(
    policy(
      "SET lock_timeout=0; BEGIN; SET lock_timeout='2s'; ROLLBACK; CREATE INDEX CONCURRENTLY a ON t (id);",
    ).diagnostics[0].code,
    "ML201",
  )
  let idle = policy(
    "SET lock_timeout='2s'; ROLLBACK; CREATE INDEX CONCURRENTLY a ON t (id);",
  )
  assert_eq(idle.diagnostics.length(), 1)
  assert_eq(idle.diagnostics[0].code, "ML104")
}

///|
test "savepoint rollback restores session and local values and keeps its target" {
  let report = policy(
    "BEGIN; SET LOCAL lock_timeout=0; SAVEPOINT a; SET LOCAL lock_timeout='2s'; ROLLBACK TO a; ROLLBACK TO SAVEPOINT a; CREATE INDEX idx ON t (id); COMMIT;",
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics[0].code, "ML201")
  let session = policy(
    "SET lock_timeout=0; BEGIN; SAVEPOINT a; SET lock_timeout='2s'; ROLLBACK TO a; COMMIT; CREATE INDEX CONCURRENTLY a ON t (id);",
  )
  assert_eq(session.diagnostics[0].code, "ML201")
}

///|
test "duplicate names select latest and release keeps effective setting" {
  let report = policy(
    "BEGIN; SET LOCAL lock_timeout=0; SAVEPOINT a; SET LOCAL lock_timeout='2s'; SAVEPOINT A; SET LOCAL lock_timeout=0; ROLLBACK TO a; RELEASE a; CREATE INDEX idx ON t (id); COMMIT;",
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.length(), 1)
  assert_eq(report.diagnostics[0].code, "ML100")
  assert_true(
    @migration_lens.review_sql(
      "BEGIN; SAVEPOINT a; SAVEPOINT b; RELEASE a; ROLLBACK TO b;",
      execution=SeparateStatements,
    ).diagnostics.any(d => d.code == "ML204"),
  )
}

///|
test "quoted savepoints preserve case and external missing targets are incomplete" {
  assert_eq(
    @migration_lens.review_sql(
      "BEGIN; SAVEPOINT \"a\"\"b\"; RELEASE \"a\"\"b\"; COMMIT;",
      execution=SeparateStatements,
    ).exit_code(),
    0,
  )
  assert_eq(
    @migration_lens.review_sql(
      "BEGIN; SAVEPOINT \"a\"; RELEASE A; COMMIT;",
      execution=SeparateStatements,
    ).exit_code(),
    0,
  )
  assert_eq(
    @migration_lens.review_sql(
      "BEGIN; SAVEPOINT \"A\"; RELEASE a;",
      execution=SeparateStatements,
    ).diagnostics[0].code,
    "ML204",
  )
  assert_eq(
    @migration_lens.review_sql(
      "ROLLBACK TO outside;",
      execution=ExistingTransaction,
    ).exit_code(),
    2,
  )
  assert_eq(
    @migration_lens.review_sql("SAVEPOINT a;", execution=SimpleQuery).diagnostics[0].code,
    "ML203",
  )
}

///|
test "reset returns to unknown default rather than assuming disabled" {
  for
    reset in ["RESET lock_timeout;", "RESET ALL;", "SET lock_timeout=DEFAULT;"] {
    assert_eq(
      policy(
        "SET lock_timeout='3s'; " +
        reset +
        "CREATE INDEX CONCURRENTLY a ON t (id);",
      ).diagnostics[0].code,
      "ML202",
    )
  }
}

///|
test "duration boundaries are checked without overflow or silent rounding" {
  for
    value in ["1", "'1ms'", "'1s'", "'1min'", "'1h'", "'1d'", "'2147483647ms'"] {
    assert_eq(
      policy(
        "SET lock_timeout=" + value + "; CREATE INDEX CONCURRENTLY a ON t (id);",
      ).exit_code(),
      0,
    )
  }
  for
    value in [
      "'2147483648ms'", "'25d'", "'1.5s'", "-1", "'infinity'", "1s", "9999999999999999999999999999999",
      "current_setting('lock_timeout')",
    ] {
    assert_eq(
      policy(
        "SET lock_timeout=" + value + "; CREATE INDEX CONCURRENTLY a ON t (id);",
      ).exit_code(),
      2,
    )
  }
  assert_eq(
    policy("SET lock_timeout='0s'; CREATE INDEX CONCURRENTLY a ON t (id);").diagnostics[0].code,
    "ML201",
  )
}

///|
test "local state does not leak between independent reviews" {
  let sql = "CREATE INDEX CONCURRENTLY a ON t (id);"
  let before = policy(sql).to_json().stringify()
  let _ = policy(
    "BEGIN; SET LOCAL lock_timeout='3s'; SAVEPOINT a; ROLLBACK TO missing;",
  )
  assert_eq(before, policy(sql).to_json().stringify())
  assert_eq(
    @migration_lens.review_sql(
      "SET lock_timeout='2s'; DROP INDEX CONCURRENTLY a;",
      execution=SimpleQuery,
    ).diagnostics[0].code,
    "ML101",
  )
}

///|
test "session SET cancels an existing local override" {
  let report = policy(
    "BEGIN; SET LOCAL lock_timeout=0; SET SESSION lock_timeout='2s'; CREATE INDEX idx ON t (id); COMMIT;",
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.length(), 1)
  assert_eq(report.diagnostics[0].code, "ML100")
  assert_eq(
    policy(
      "BEGIN; SET lock_timeout='3s'; COMMIT; CREATE INDEX CONCURRENTLY idx ON t (id);",
    ).exit_code(),
    0,
  )
}
