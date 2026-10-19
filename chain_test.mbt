///|
test "chaining starts a new explicit transaction and keeps concurrent restrictions" {
  for end in ["COMMIT", "END", "ROLLBACK", "ABORT"] {
    for suffix in ["", " WORK", " TRANSACTION"] {
      let sql = "BEGIN; " +
        end +
        suffix +
        " AND CHAIN; DROP INDEX CONCURRENTLY a; COMMIT;"
      let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
      assert_true(report.complete)
      assert_eq(report.diagnostics.length(), 1)
      assert_eq(report.diagnostics[0].code, "ML101")
      assert_eq(
        @migration_lens.review_sql(
          "BEGIN; " + end + suffix + " AND NO CHAIN; DROP INDEX CONCURRENTLY a;",
          execution=SeparateStatements,
        ).exit_code(),
        0,
      )
    }
  }
}

///|
test "chaining resets local settings and snapshots the new session baseline" {
  let report = @migration_lens.review_sql(
    "SET lock_timeout=0; BEGIN; SET lock_timeout='2s'; SET LOCAL lock_timeout=0; END AND CHAIN; ABORT; CREATE INDEX CONCURRENTLY a ON t (id);",
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_eq(report.exit_code(), 0)
  let rollback = @migration_lens.review_sql(
    "SET lock_timeout=0; BEGIN; SET lock_timeout='2s'; ABORT AND CHAIN; END; CREATE INDEX CONCURRENTLY a ON t (id);",
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_eq(rollback.diagnostics[0].code, "ML201")
  let marks = @migration_lens.review_sql(
    "BEGIN; SAVEPOINT a; END AND CHAIN; ROLLBACK TO a;",
    execution=SeparateStatements,
  )
  assert_eq(marks.diagnostics[0].code, "ML204")
}

///|
test "idle chain fails and unknown state is never repaired by chaining" {
  let idle = @migration_lens.review_sql(
    "END AND CHAIN; DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
  )
  assert_eq(idle.exit_code(), 2)
  assert_eq(idle.diagnostics[0].code, "ML106")
  assert_eq(idle.diagnostics[1].code, "ML102")
  let implicit = @migration_lens.review_sql(
    "SET lock_timeout=100; END AND CHAIN;",
    execution=SimpleQuery,
  )
  assert_eq(implicit.diagnostics[0].code, "ML106")
  let open = @migration_lens.review_sql(
    "BEGIN; COMMIT AND CHAIN;",
    execution=SeparateStatements,
  )
  assert_eq(open.diagnostics[0].code, "ML103")
  let unknown = @migration_lens.review_sql(
    "SELECT 1; ABORT AND CHAIN; DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
  )
  assert_eq(unknown.exit_code(), 2)
  assert_true(unknown.diagnostics.any(d => d.code == "ML102"))
  let external = @migration_lens.review_sql(
    "END AND CHAIN; ABORT;",
    execution=ExistingTransaction,
  )
  assert_eq(external.diagnostics.length(), 1)
  assert_eq(external.diagnostics[0].code, "ML105")
}
