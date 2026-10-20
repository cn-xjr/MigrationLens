///|
test "VACUUM follows separate simple explicit external and unknown dispatch" {
  assert_eq(
    @migration_lens.review_sql("VACUUM events;", execution=SeparateStatements).diagnostics.map(d => {
        d.code
      },
    ),
    ["ML150", "ML152"],
  )
  assert_eq(
    @migration_lens.review_sql("VACUUM events;", execution=SimpleQuery).diagnostics.map(d => {
        d.code
      },
    ),
    ["ML150", "ML152"],
  )
  for
    (sql, execution) in [
      ("SET lock_timeout=100; VACUUM events;", @migration_lens.SimpleQuery),
      ("BEGIN READ WRITE; VACUUM events;", @migration_lens.SeparateStatements),
      ("VACUUM events;", @migration_lens.ExistingTransaction),
    ] {
    let report = @migration_lens.review_sql(sql, execution~)
    assert_true(report.complete)
    assert_eq(report.diagnostics[0].code, "ML151")
    assert_eq(report.diagnostics[0].severity, Error)
  }
  let unknown = @migration_lens.review_sql("VACUUM events;", execution=Unknown)
  assert_eq(unknown.exit_code(), 2)
  assert_eq(unknown.diagnostics[1].code, "ML151")
  assert_eq(unknown.diagnostics[1].severity, Incomplete)
}

///|
test "VACUUM full truncate and index-cleanup options have explicit effects" {
  for full in ["TRUE", "ON", "1", "FALSE", "OFF", "0"] {
    for truncate in ["TRUE", "FALSE"] {
      let sql = "VACUUM (FULL \{full}, TRUNCATE \{truncate}, INDEX_CLEANUP OFF) public.events;"
      let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
      let enabled = full == "TRUE" || full == "ON" || full == "1"
      assert_true(report.complete)
      assert_eq(report.diagnostics[0].code, "ML150")
      assert_eq(report.diagnostics[0].message.contains("FULL"), enabled)
      assert_eq(
        report.diagnostics.any(d => d.code == "ML152"),
        !enabled && truncate == "TRUE",
      )
      assert_eq(report.diagnostics.any(d => d.code == "ML153"), !enabled)
    }
  }
  for setting in ["AUTO", "ON", "OFF"] {
    let report = @migration_lens.review_sql(
      "VACUUM (INDEX_CLEANUP \{setting}, TRUNCATE FALSE) events;",
      execution=SeparateStatements,
    )
    assert_eq(report.diagnostics.length(), if setting == "OFF" { 2 } else { 1 })
  }
}

///|
test "VACUUM legacy option subsets and maintenance target grammar compose" {
  for mask in 0..<16 {
    let out = StringBuilder()
    out.write_string("VACUUM")
    for i, flag in ["FULL", "FREEZE", "VERBOSE", "ANALYZE"] {
      if (mask & (1 << i)) != 0 {
        out.write_string(" " + flag)
      }
    }
    out.write_string(" ONLY public.events")
    if (mask & 8) != 0 {
      out.write_string(" (id, created_at)")
    }
    out.write_string(", \"schema;名\".\"table,😀\"*;")
    let report = @migration_lens.review_sql(
      out.to_string(),
      execution=SeparateStatements,
    )
    assert_true(report.complete, msg=out.to_string())
    assert_eq(report.diagnostics[0].message.contains("FULL"), (mask & 1) != 0)
    assert_eq(report.diagnostics.any(d => d.code == "ML152"), (mask & 1) == 0)
  }
}

///|
test "VACUUM skip-locked never disables timeout policy or taints valid following SQL" {
  let sql = "SET lock_timeout=100; VACUUM (SKIP_LOCKED, TRUNCATE FALSE) events; DROP INDEX CONCURRENTLY a;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), ["ML150"])
  assert_true(report.diagnostics[0].help.contains("still wait"))
  let unknown_timeout = @migration_lens.review_sql(
    "VACUUM (SKIP_LOCKED, TRUNCATE FALSE) events;",
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_eq(unknown_timeout.diagnostics.map(d => d.code), ["ML202", "ML150"])
  let too_long = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=99,
  )
  assert_eq(too_long.diagnostics.map(d => d.code), ["ML205", "ML150", "ML205"])
}

///|
test "invalid VACUUM transaction context is not repaired by a later COMMIT" {
  let report = @migration_lens.review_sql(
    "BEGIN; SET LOCAL lock_timeout=100; VACUUM events; COMMIT; DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_eq(report.exit_code(), 2)
  assert_true(
    report.diagnostics.any(d => d.code == "ML151" && d.severity == Error),
  )
  assert_true(report.diagnostics.any(d => d.code == "ML102"))
  assert_true(report.diagnostics.any(d => d.code == "ML202"))
  assert_true(!report.diagnostics.any(d => d.code == "ML103"))
}

///|
test "VACUUM rejects unsupported options and lossy column or relation suffixes" {
  for
    sql in [
      "VACUUM ();", "VACUUM (FULL,);", "VACUUM (FULL FALSE TRUE) events;", "VACUUM (FULL, FULL) events;",
      "VACUUM (FULL 'on') events;", "VACUUM (INDEX_CLEANUP) events;", "VACUUM (INDEX_CLEANUP TRUE) events;",
      "VACUUM (INDEX_CLEANUP AUTO, INDEX_CLEANUP ON) events;", "VACUUM (PARALLEL 0) events;",
      "VACUUM (BUFFER_USAGE_LIMIT '1MB') events;", "VACUUM (PROCESS_TOAST OFF) events;",
      "VACUUM (ONLY_DATABASE_STATS);", "VACUUM (DISABLE_PAGE_SKIPPING) events;",
      "VACUUM events (id);", "VACUUM (ANALYZE FALSE) events(id);", "VACUUM ANALYZE events ();",
      "VACUUM ANALYZE events(id,);", "VACUUM ANALYZE events(id + 1);", "VACUUM ONLY events*;",
      "VACUUM events,;", "VACUUM db.public.events;", "VACUUM FULL FULL events;",
      "VACUUM (FULL) ANALYZE events;", "VACUUM FULL events GARBAGE;", "VACUUM (FULL;",
    ] {
    let report = @migration_lens.review_sql(
      sql + " DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML003"), msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML102"), msg=sql)
  }
  assert_true(
    @migration_lens.review_sql(
      "VACUUM (ANALYZE, TRUNCATE FALSE) events(id);",
      execution=SeparateStatements,
    ).complete,
  )
}

///|
test "VACUUM database scope and target-count boundaries preserve deterministic archives" {
  let all = @migration_lens.review_sql("VACUUM;", execution=SeparateStatements)
  assert_eq(all.diagnostics.map(d => d.code), ["ML150", "ML152", "ML154"])
  for count in 1..<=16 {
    let targets : Array[String] = []
    for i in 0..<count {
      targets.push("public.t\{i} (id)")
    }
    let sql = "VACUUM (ANALYZE, TRUNCATE FALSE) " + targets.join(", ") + ";"
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_true(report.complete)
    assert_eq(report.statements, 1)
    assert_eq(report.diagnostics.map(d => d.code), ["ML150"])
    assert_eq(
      @migration_lens.Report::parse_json(report.to_json().stringify()).unwrap(),
      report,
    )
    assert_eq(
      report.to_json(),
      @migration_lens.review_sql(sql, execution=SeparateStatements).to_json(),
    )
  }
}

///|
test "VACUUM findings retain original UTF-16 source in reports batch archives and SARIF" {
  let sql = "-- 😀\r\nVACUUM (FULL FALSE, INDEX_CLEANUP OFF) public.\"表😀\";"
  let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
  for d in report.diagnostics {
    assert_eq(
      sql[d.span.start:d.span.end].to_owned(),
      "VACUUM (FULL FALSE, INDEX_CLEANUP OFF) public.\"表😀\";",
    )
  }
  assert_true(report.to_sarif("migrations/vacuum.sql") is Ok(_))
  let batch = @migration_lens.review_migrations(
    [
      @migration_lens.Migration::new(
        "vacuum.sql",
        sql,
        execution=SeparateStatements,
      ),
    ][:],
  )
  assert_eq(
    @migration_lens.BatchReport::parse_json(batch.to_json().stringify())
    .unwrap()
    .to_json(),
    batch.to_json(),
  )
  let delta = @migration_lens.compare_batches(batch, batch).unwrap()
  assert_eq(delta.exit_code(), 0)
  assert_eq(delta.files[0].retained, 3)
}
