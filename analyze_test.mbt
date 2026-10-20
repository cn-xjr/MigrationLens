///|
test "ANALYZE consumes qualified quoted relation and column lists" {
  for
    sql in [
      "ANALYZE public.events;", "ANALYZE ONLY public.events (id, created_at);", "ANALYZE events* (id), ONLY public.users (name);",
      "ANALYZE VERBOSE \"schema;名\".\"table,😀\" (\"select\", \"col\"\"x\");",
      "ANALYZE (VERBOSE OFF, SKIP_LOCKED ON) events;",
    ] {
    let report = @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      initial_lock_timeout_ms=100,
      max_lock_timeout_ms=100,
    )
    assert_true(report.complete, msg=sql)
    assert_eq(report.diagnostics.map(d => d.code), ["ML140"], msg=sql)
    assert_eq(report.source, sql)
    assert_eq(
      @migration_lens.Report::parse_json(report.to_json().stringify()).unwrap(),
      report,
    )
  }
}

///|
test "ANALYZE database-wide scope and explicit boolean effects are visible" {
  for
    sql in [
      "ANALYZE;", "ANALYZE VERBOSE;", "ANALYZE (SKIP_LOCKED);", "ANALYZE (VERBOSE 0);",
    ] {
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_true(report.complete)
    assert_eq(report.diagnostics.map(d => d.code), ["ML140", "ML141"])
  }
  for value in ["TRUE", "ON", "1", "FALSE", "OFF", "0"] {
    let report = @migration_lens.review_sql(
      "ANALYZE (SKIP_LOCKED \{value}, VERBOSE) events;",
      execution=SeparateStatements,
      require_lock_timeout=true,
    )
    assert_eq(report.diagnostics.map(d => d.code), ["ML202", "ML140"])
    assert_eq(
      report.diagnostics[1].help.contains("may omit busy relations"),
      value == "TRUE" || value == "ON" || value == "1",
    )
  }
}

///|
test "ANALYZE preserves transaction and scoped timeout state" {
  let sql = "BEGIN READ WRITE; SET LOCAL lock_timeout=100; SAVEPOINT a; SET LOCAL lock_timeout=0; ROLLBACK TO a; ANALYZE events; COMMIT; CREATE INDEX CONCURRENTLY a ON events(id);"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML140", "ML202"])
  let simple = @migration_lens.review_sql(sql, execution=SimpleQuery)
  assert_true(simple.complete)
  assert_eq(simple.diagnostics.map(d => d.code), ["ML140", "ML101"])
  let external = @migration_lens.review_sql(
    "ANALYZE events;",
    execution=ExistingTransaction,
  )
  assert_eq(external.diagnostics.map(d => d.code), ["ML140"])
}

///|
test "ANALYZE malformed or unsupported data is never silently discarded" {
  for
    sql in [
      "ANALYZE ();", "ANALYZE (VERBOSE,);", "ANALYZE (VERBOSE;", "ANALYZE (VERBOSE ON OFF) events;",
      "ANALYZE (VERBOSE, VERBOSE) events;", "ANALYZE (SKIP_LOCKED 'true') events;",
      "ANALYZE (BUFFER_USAGE_LIMIT '1MB') events;", "ANALYZE (UNKNOWN) events;",
      "ANALYZE events ();", "ANALYZE events (id,);", "ANALYZE events (id;", "ANALYZE events (id + 1);",
      "ANALYZE events (t.id);", "ANALYZE ONLY;", "ANALYZE ONLY events*;", "ANALYZE catalog.public.events;",
      "ANALYZE events,;", "ANALYZE events GARBAGE;", "ANALYZE (VERBOSE) VERBOSE events;",
    ] {
    let report = @migration_lens.review_sql(
      sql + " DROP INDEX CONCURRENTLY x;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML003"), msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML102"), msg=sql)
  }
  assert_true(
    @migration_lens.review_sql("ANALYZE events;", execution=SeparateStatements).complete,
  )
}

///|
test "ANALYZE diagnostics preserve source spans deterministic archives and SARIF" {
  let sql = "-- 😀\r\nANALYZE (SKIP_LOCKED) public.\"event😀\" (id);"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_eq(report.diagnostics.length(), 2)
  for d in report.diagnostics {
    assert_eq(
      sql[d.span.start:d.span.end].to_owned(),
      "ANALYZE (SKIP_LOCKED) public.\"event😀\" (id);",
    )
  }
  assert_eq(@json.parse(report.to_json().stringify()), report.to_json())
  assert_eq(
    report.to_json(),
    @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      max_lock_timeout_ms=100,
    ).to_json(),
  )
  assert_true(report.to_sarif("migrations/analyze.sql") is Ok(_))
}
