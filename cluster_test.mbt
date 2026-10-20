///|
test "CLUSTER options names and targeted transaction semantics" {
  for option in ["", "VERBOSE ", "(VERBOSE) ", "(VERBOSE OFF) ", "(VERBOSE 1) "] {
    for
      target in [
        "events", "public.events USING events_id", "\"s;名\".\"t😀\" USING \"i,名\"",
      ] {
      let sql = "SET lock_timeout=100; CLUSTER " +
        option +
        target +
        "; DROP INDEX CONCURRENTLY old_idx;"
      let report = @migration_lens.review_sql(
        sql,
        execution=SeparateStatements,
        max_lock_timeout_ms=100,
      )
      assert_true(report.complete, msg=sql)
      assert_eq(report.diagnostics.map(d => d.code), ["ML160", "ML163"])
      let wrapped = @migration_lens.review_sql(
        "BEGIN; CLUSTER " + option + target + "; COMMIT;",
        execution=SeparateStatements,
      )
      assert_eq(wrapped.diagnostics.map(d => d.code), ["ML160", "ML163"])
    }
  }
}

///|
test "database-wide CLUSTER enforces known blocks and preserves uncertainty" {
  let standalone = @migration_lens.review_sql(
    "CLUSTER;",
    execution=SeparateStatements,
  )
  assert_eq(standalone.diagnostics.map(d => d.code), ["ML160", "ML161"])
  for
    (sql, execution) in [
      ("BEGIN; CLUSTER;", @migration_lens.SeparateStatements),
      ("SET lock_timeout=100; CLUSTER;", @migration_lens.SimpleQuery),
      ("CLUSTER;", @migration_lens.ExistingTransaction),
    ] {
    let report = @migration_lens.review_sql(sql, execution~)
    assert_true(report.complete)
    assert_eq(report.diagnostics[0].code, "ML162")
    assert_eq(report.diagnostics[0].severity, Error)
  }
  let unknown = @migration_lens.review_sql(
    "CLUSTER; COMMIT; DROP INDEX CONCURRENTLY a;",
    execution=Unknown,
  )
  assert_eq(unknown.exit_code(), 2)
  assert_true(
    unknown.diagnostics.any(d => d.code == "ML162" && d.severity == Incomplete),
  )
  assert_true(unknown.diagnostics.any(d => d.code == "ML102"))
}

///|
test "CLUSTER rejects every unsupported suffix without losing later diagnostics" {
  for
    sql in [
      "CLUSTER () events", "CLUSTER (VERBOSE TRUE, VERBOSE FALSE) events", "CLUSTER (VERBOSE 'on') events",
      "CLUSTER (SKIP_LOCKED) events", "CLUSTER events USING", "CLUSTER events USING s.idx",
      "CLUSTER events, other", "CLUSTER ONLY events", "CLUSTER events*", "CLUSTER events(id)",
      "CLUSTER db.public.events", "CLUSTER idx ON events", "CLUSTER events CASCADE",
    ] {
    let report = @migration_lens.review_sql(
      sql + "; DROP INDEX CONCURRENTLY old_idx;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_eq(report.diagnostics[0].code, "ML003", msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML102"))
  }
}

///|
test "CLUSTER timeout rollback scope spans and archives retain findings" {
  let sql = "-- 😀\r\nBEGIN; SET LOCAL lock_timeout=100; CLUSTER public.events USING events_id; ROLLBACK; CLUSTER events;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
    initial_lock_timeout_ms=200,
  )
  assert_eq(report.diagnostics.map(d => d.code), [
    "ML160", "ML163", "ML205", "ML160", "ML163",
  ])
  assert_eq(
    report.source[report.diagnostics[0].span.start:report.diagnostics[0].span.end].to_owned(),
    "CLUSTER public.events USING events_id;",
  )
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
      initial_lock_timeout_ms=200,
    ).to_json(),
  )
  assert_true(report.to_sarif("migrations/cluster.sql") is Ok(_))
}
