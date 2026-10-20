///|
test "index-backed constraints distinguish primary keys and deferrable timing" {
  for kind in ["UNIQUE", "PRIMARY KEY"] {
    for named in ["", "CONSTRAINT \"key,😀\" "] {
      for
        (timing, deferrable) in [
          ("", false),
          (" NOT DEFERRABLE", false),
          (" INITIALLY IMMEDIATE", false),
          (" NOT DEFERRABLE INITIALLY IMMEDIATE", false),
          (" DEFERRABLE", true),
          (" DEFERRABLE INITIALLY IMMEDIATE", true),
          (" DEFERRABLE INITIALLY DEFERRED", true),
        ] {
        let sql = "ALTER TABLE public.events ADD " +
          named +
          kind +
          " USING INDEX \"idx;名\"" +
          timing +
          ";"
        let report = @migration_lens.review_sql(
          sql,
          execution=SeparateStatements,
        )
        assert_true(report.complete, msg=sql)
        assert_eq(report.diagnostics[0].code, "ML190")
        assert_eq(report.diagnostics[1].code, "ML191")
        assert_eq(
          report.diagnostics.any(d => d.code == "ML192"),
          kind == "PRIMARY KEY",
        )
        assert_eq(report.diagnostics.any(d => d.code == "ML193"), deferrable)
      }
    }
  }
}

///|
test "concurrent unique build and attachment preserve dispatch distinction" {
  let sql = "SET lock_timeout=100; CREATE UNIQUE INDEX CONCURRENTLY events_key ON events(id); ALTER TABLE events ADD CONSTRAINT events_unique UNIQUE USING INDEX events_key;"
  let separate = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(separate.complete)
  assert_eq(separate.diagnostics.map(d => d.code), ["ML190", "ML191"])
  let simple = @migration_lens.review_sql(
    sql,
    execution=SimpleQuery,
    max_lock_timeout_ms=100,
  )
  assert_true(simple.diagnostics.any(d => d.code == "ML101"))
  for prefix in ["IF EXISTS ", "ONLY ", "IF EXISTS ONLY ", ""] {
    let report = @migration_lens.review_sql(
      "ALTER TABLE " +
      prefix +
      "\"s;名\".\"t😀\" ADD UNIQUE USING INDEX idx;",
      execution=ExistingTransaction,
    )
    assert_eq(report.diagnostics.map(d => d.code), ["ML190", "ML191"])
  }
}

///|
test "attachment rejects mixed actions invalid attributes and lossy name forms" {
  for
    action in [
      "ADD UNIQUE USING INDEX", "ADD CONSTRAINT UNIQUE USING INDEX a", "ADD PRIMARY USING INDEX a",
      "ADD UNIQUE USING INDEX s.a", "ADD UNIQUE USING INDEX a NOT VALID", "ADD UNIQUE USING INDEX a, ADD UNIQUE USING INDEX b",
      "ADD UNIQUE USING INDEX a, DROP COLUMN id", "ADD UNIQUE USING INDEX a INCLUDE (id)",
      "ADD UNIQUE USING INDEX a INITIALLY DEFERRED", "ADD UNIQUE USING INDEX a NOT DEFERRABLE INITIALLY DEFERRED",
      "ADD UNIQUE USING INDEX a DEFERRABLE DEFERRABLE", "ADD UNIQUE (id)",
    ] {
    let sql = "ALTER TABLE events " +
      action +
      "; DROP INDEX CONCURRENTLY old_idx;"
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_eq(report.exit_code(), 2, msg=action)
    assert_eq(report.diagnostics[0].code, "ML003", msg=action)
    assert_true(!report.diagnostics.any(d => d.code == "ML190"))
    assert_true(report.diagnostics.any(d => d.code == "ML102"))
  }
}

///|
test "attachment preserves timeout savepoint rollback and original source" {
  let sql = "-- 😀\r\nBEGIN; SET LOCAL lock_timeout=100; SAVEPOINT s; ALTER TABLE events ADD PRIMARY KEY USING INDEX idx; ROLLBACK TO s; COMMIT; DROP INDEX CONCURRENTLY old_idx;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
    initial_lock_timeout_ms=101,
  )
  assert_eq(report.diagnostics.map(d => d.code), [
    "ML190", "ML191", "ML192", "ML205",
  ])
  assert_eq(
    report.source[report.diagnostics[0].span.start:report.diagnostics[0].span.end].to_owned(),
    "ALTER TABLE events ADD PRIMARY KEY USING INDEX idx;",
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
      initial_lock_timeout_ms=101,
    ).to_json(),
  )
  assert_true(report.to_sarif("migrations/attach.sql") is Ok(_))
}
