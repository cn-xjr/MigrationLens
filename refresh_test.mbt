///|
test "materialized-view refresh variants retain transaction and timeout state" {
  for concurrent in [false, true] {
    for suffix in ["", " WITH DATA"] {
      for target in ["stats", "public.stats", "\"s;名\".\"view😀\""] {
        let sql = "BEGIN; SET LOCAL lock_timeout=100; REFRESH MATERIALIZED VIEW " +
          (if concurrent { "CONCURRENTLY " } else { "" }) +
          target +
          suffix +
          "; COMMIT; DROP INDEX CONCURRENTLY old_idx;"
        let report = @migration_lens.review_sql(
          sql,
          execution=SeparateStatements,
          max_lock_timeout_ms=100,
          initial_lock_timeout_ms=100,
        )
        assert_true(report.complete, msg=sql)
        assert_eq(
          report.diagnostics.map(d => d.code),
          if concurrent {
            ["ML170", "ML171"]
          } else {
            ["ML170"]
          },
        )
        assert_eq(
          report.diagnostics[0].message.contains("allowing"),
          concurrent,
        )
      }
    }
  }
}

///|
test "refresh WITH NO DATA warns about loss of readability" {
  let report = @migration_lens.review_sql(
    "REFRESH MATERIALIZED VIEW public.stats WITH NO DATA;",
    execution=SeparateStatements,
  )
  assert_eq(report.diagnostics.map(d => d.code), ["ML170", "ML172"])
  assert_true(report.diagnostics[1].help.contains("does not retain"))
  let recovered = @migration_lens.review_sql(
    "REFRESH MATERIALIZED VIEW stats WITH NO DATA; REFRESH MATERIALIZED VIEW stats WITH DATA;",
    execution=SimpleQuery,
  )
  assert_true(recovered.complete)
  assert_eq(recovered.diagnostics.map(d => d.code), ["ML170", "ML172", "ML170"])
}

///|
test "refresh rejects incompatible flags and taints later context" {
  let invalid = @migration_lens.review_sql(
    "REFRESH MATERIALIZED VIEW CONCURRENTLY stats WITH NO DATA;",
    execution=SeparateStatements,
  )
  assert_true(invalid.complete)
  assert_eq(invalid.diagnostics.map(d => d.code), ["ML173"])
  assert_eq(invalid.diagnostics[0].severity, Error)
  let later = @migration_lens.review_sql(
    invalid.source + " COMMIT; DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
  )
  assert_eq(later.exit_code(), 2)
  assert_true(later.diagnostics.any(d => d.code == "ML102"))
}

///|
test "refresh unsupported syntax remains incomplete and cannot reset uncertainty" {
  for
    sql in [
      "REFRESH MATERIALIZED VIEW", "REFRESH MATERIALIZED VIEW CONCURRENTLY", "REFRESH MATERIALIZED VIEW IF EXISTS stats",
      "REFRESH MATERIALIZED VIEW ONLY stats", "REFRESH MATERIALIZED VIEW a, b", "REFRESH MATERIALIZED VIEW a WITH",
      "REFRESH MATERIALIZED VIEW a WITH NO", "REFRESH MATERIALIZED VIEW a WITH DATA CASCADE",
      "REFRESH MATERIALIZED VIEW a CONCURRENTLY", "REFRESH MATERIALIZED VIEW db.public.stats",
      "REFRESH MATERIALIZED VIEW a(id)", "REFRESH VIEW a",
    ] {
    let report = @migration_lens.review_sql(
      sql + "; REFRESH MATERIALIZED VIEW stats; DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_eq(report.diagnostics[0].code, "ML003", msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML170"))
    assert_true(report.diagnostics.any(d => d.code == "ML102"))
  }
}

///|
test "concurrent refresh still checks effective lock timeout including rollback" {
  let sql = "BEGIN; SET LOCAL lock_timeout=100; REFRESH MATERIALIZED VIEW CONCURRENTLY stats; ROLLBACK; REFRESH MATERIALIZED VIEW stats;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
    initial_lock_timeout_ms=101,
  )
  assert_eq(report.diagnostics.map(d => d.code), [
    "ML170", "ML171", "ML205", "ML170",
  ])
  let unknown = @migration_lens.review_sql(
    "REFRESH MATERIALIZED VIEW CONCURRENTLY stats;",
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_eq(unknown.diagnostics.map(d => d.code), ["ML202", "ML170", "ML171"])
}

///|
test "refresh Unicode spans and archive outputs are deterministic and lossless" {
  let sql = "-- 😀\r\nREFRESH MATERIALIZED VIEW \"统计;😀\" WITH NO DATA;"
  let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
  assert_eq(
    @migration_lens.Report::parse_json(report.to_json().stringify()),
    Ok(report),
  )
  assert_eq(
    report.to_json(),
    @migration_lens.review_sql(sql, execution=SeparateStatements).to_json(),
  )
  assert_eq(
    report.source[report.diagnostics[0].span.start:report.diagnostics[0].span.end].to_owned(),
    "REFRESH MATERIALIZED VIEW \"统计;😀\" WITH NO DATA;",
  )
  assert_true(report.to_sarif("migrations/refresh.sql") is Ok(_))
}
