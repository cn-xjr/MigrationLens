///|
test "single-index tablespace moves preserve names spans and downstream dispatch" {
  for name in ["old", "public.old", "\"s;one\".\"i,one\"", "\"中文😀\""] {
    for destination in ["pg_default", "\"archive;one\"", "\"q\"\"name\""] {
      let sql = "-- 😀\r\nALTER INDEX IF EXISTS " +
        name +
        " SET TABLESPACE " +
        destination +
        "; DROP INDEX CONCURRENTLY retired;"
      let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
      assert_true(report.complete, msg=sql)
      assert_eq(report.diagnostics.length(), 1)
      assert_eq(report.diagnostics[0].code, "ML112")
      assert_eq(report.diagnostics[0].span.start, 7)
      assert_eq(report.source, sql)
      assert_true(
        report.diagnostics[0].message.contains(
          "ACCESS EXCLUSIVE lock on the index",
        ),
      )
      assert_true(report.to_sarif("migrations/move.sql") is Ok(_))
      assert_eq(
        @migration_lens.Report::parse_json(report.to_json().stringify()).unwrap(),
        report,
      )
      assert_eq(
        report.to_json().stringify(),
        @migration_lens.review_sql(sql, execution=SeparateStatements)
        .to_json()
        .stringify(),
      )
      let batch = @migration_lens.review_sql(sql, execution=SimpleQuery)
      assert_true(batch.diagnostics.any(d => d.code == "ML101"))
    }
  }
}

///|
test "tablespace moves use effective timeout scopes and preserve transaction state" {
  let sql = "BEGIN; SET LOCAL lock_timeout=100; ALTER INDEX a SET TABLESPACE pg_default; COMMIT; DROP INDEX CONCURRENTLY retired;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics[0].code, "ML112")
  assert_eq(report.diagnostics[1].code, "ML202")
  assert_eq(report.diagnostics.length(), 2)
  for (initial, code) in [(0, "ML201"), (101, "ML205"), (100, "ML112")] {
    let report = @migration_lens.review_sql(
      "ALTER INDEX a SET TABLESPACE pg_default;",
      execution=ExistingTransaction,
      initial_lock_timeout_ms=initial,
      max_lock_timeout_ms=100,
    )
    assert_true(report.complete)
    assert_eq(report.diagnostics[0].code, code)
  }
  let rollback = @migration_lens.review_sql(
    "BEGIN; SET LOCAL lock_timeout=100; SAVEPOINT s; SET LOCAL lock_timeout=0; ROLLBACK TO s; ALTER INDEX a SET TABLESPACE pg_default; COMMIT;",
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_eq(rollback.diagnostics.length(), 1)
  assert_eq(rollback.diagnostics[0].code, "ML112")
  let unknown = @migration_lens.review_sql(
    "ALTER INDEX a SET TABLESPACE pg_default;",
    execution=Unknown,
    require_lock_timeout=true,
  )
  assert_eq(unknown.exit_code(), 2)
  assert_true(unknown.diagnostics.any(d => d.code == "ML202"))
}

///|
test "unsupported tablespace clauses never become passing partial moves" {
  for
    sql in [
      "ALTER INDEX SET TABLESPACE s;", "ALTER INDEX IF a SET TABLESPACE s;", "ALTER INDEX a SET TABLESPACE;",
      "ALTER INDEX a SET TABLESPACE s.t;", "ALTER INDEX a SET TABLESPACE s NOWAIT;",
      "ALTER INDEX a SET TABLESPACE 's';", "ALTER INDEX a SET TABLESPACE \"\";",
      "ALTER INDEX a SET TABLESPACE s, b;", "ALTER INDEX a SET TABLESPACE s RENAME TO b;",
      "ALTER INDEX ALL IN TABLESPACE s SET TABLESPACE t NOWAIT;", "ALTER INDEX ALL IN TABLESPACE s OWNED BY owner SET TABLESPACE t;",
      "ALTER INDEX a.b.c SET TABLESPACE s;", "ALTER INDEX a SET (tablespace=s);",
      "ALTER TABLE a SET TABLESPACE s;",
    ] {
    let report = @migration_lens.review_sql(
      sql + " COMMIT; DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_eq(report.diagnostics[0].code, "ML003", msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML102"), msg=sql)
  }
  let valid = @migration_lens.review_sql(
    "ALTER INDEX a /* nested /* one */ */ SET TABLESPACE pg_default;",
    execution=SeparateStatements,
  )
  assert_true(valid.complete)
  assert_eq(valid.diagnostics[0].code, "ML112")
}
