///|
test "transaction mode permutations preserve transaction and timeout semantics" {
  for
    prefix in ["BEGIN", "BEGIN WORK", "BEGIN TRANSACTION", "START TRANSACTION"] {
    for
      isolation in [
        "SERIALIZABLE", "REPEATABLE READ", "READ COMMITTED", "READ UNCOMMITTED",
      ] {
      for separator in [", ", " "] {
        let source = "\{prefix} ISOLATION LEVEL \{isolation}\{separator}READ WRITE\{separator}NOT DEFERRABLE; SET LOCAL lock_timeout=100; DROP INDEX a; COMMIT; DROP INDEX CONCURRENTLY b;"
        let report = @migration_lens.review_sql(
          source,
          execution=SeparateStatements,
          max_lock_timeout_ms=100,
        )
        assert_true(report.complete)
        assert_eq(report.diagnostics.map(d => d.code), ["ML100", "ML202"])
        assert_eq(report.source, source)
        assert_eq(
          @migration_lens.Report::parse_json(report.to_json().stringify()).unwrap(),
          report,
        )
      }
    }
  }
  let reordered = @migration_lens.review_sql(
    "BEGIN NOT DEFERRABLE READ WRITE, ISOLATION LEVEL SERIALIZABLE; ROLLBACK;",
    execution=SeparateStatements,
  )
  assert_eq(reordered.exit_code(), 0)
}

///|
test "read-only and deferrable modes have actionable limitations and original spans" {
  let source = "-- 😀\r\nBEGIN ISOLATION LEVEL SERIALIZABLE, READ ONLY, DEFERRABLE; COMMIT;"
  let report = @migration_lens.review_sql(source, execution=SeparateStatements)
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML130", "ML131"])
  for d in report.diagnostics {
    assert_eq(
      source[d.span.start:d.span.end].to_owned(),
      "BEGIN ISOLATION LEVEL SERIALIZABLE, READ ONLY, DEFERRABLE;",
    )
    assert_eq(d.severity, Warning)
  }
  assert_true(report.to_text().contains("lock_timeout"))
  assert_eq(@json.parse(report.to_json().stringify()), report.to_json())
  assert_true(report.to_sarif("migrations/modes.sql") is Ok(_))
}

///|
test "mode-bearing transaction starts retain simple and external dispatch rules" {
  let source = "BEGIN READ WRITE; DROP INDEX CONCURRENTLY a; COMMIT; DROP INDEX CONCURRENTLY b;"
  let separate = @migration_lens.review_sql(
    source,
    execution=SeparateStatements,
  )
  let simple = @migration_lens.review_sql(source, execution=SimpleQuery)
  assert_eq(separate.diagnostics.filter(d => d.code == "ML101").length(), 1)
  assert_eq(simple.diagnostics.filter(d => d.code == "ML101").length(), 2)
  let nested = @migration_lens.review_sql(
    "BEGIN READ ONLY; COMMIT;",
    execution=ExistingTransaction,
  )
  assert_eq(nested.diagnostics.map(d => d.code), ["ML130", "ML104", "ML105"])
  let unknown = @migration_lens.review_sql(
    "BEGIN READ WRITE; COMMIT; DROP INDEX CONCURRENTLY a;",
    execution=Unknown,
  )
  assert_eq(unknown.exit_code(), 2)
  assert_true(unknown.diagnostics.any(d => d.code == "ML102"))
}

///|
test "mode-bearing starts preserve savepoint and chain timeout baselines" {
  let source = "SET lock_timeout=100; START TRANSACTION READ WRITE; SAVEPOINT a; SET LOCAL lock_timeout=0; ROLLBACK TO a; DROP INDEX x; COMMIT AND CHAIN; DROP INDEX y; ROLLBACK;"
  let report = @migration_lens.review_sql(
    source,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML100", "ML100"])
}

///|
test "unrecognized or repeated transaction modes never become a passing prefix" {
  for
    sql in [
      "BEGIN, READ WRITE;", "BEGIN READ WRITE,;", "BEGIN ISOLATION LEVEL;", "BEGIN ISOLATION LEVEL READ;",
      "BEGIN READ;", "BEGIN NOT;", "START READ WRITE;", "BEGIN READ ONLY READ WRITE;",
      "BEGIN DEFERRABLE NOT DEFERRABLE;", "BEGIN NOT DEFERRABLE DEFERRABLE;", "BEGIN ISOLATION LEVEL SERIALIZABLE, ISOLATION LEVEL READ COMMITTED;",
      "BEGIN READ WRITE,, NOT DEFERRABLE;", "BEGIN READ WRITE GARBAGE;", "BEGIN READ 'ONLY';",
      "BEGIN \"READ\" ONLY;", "START TRANSACTION WORK;",
    ] {
    let report = @migration_lens.review_sql(
      sql + "DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML003"), msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML102"), msg=sql)
  }
  assert_eq(
    @migration_lens.review_sql(
      "BEGIN READ WRITE; COMMIT;",
      execution=SeparateStatements,
    ).exit_code(),
    0,
  )
}
