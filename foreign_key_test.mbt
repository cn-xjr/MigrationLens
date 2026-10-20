///|
test "foreign-key installation distinguishes deferred historical validation" {
  for suffix in ["", " NOT VALID"] {
    for prefix in ["", "IF EXISTS ONLY "] {
      let sql = "ALTER TABLE " +
        prefix +
        "public.events ADD CONSTRAINT events_account_fk FOREIGN KEY (account_id) REFERENCES public.accounts(id)" +
        suffix +
        ";"
      let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
      assert_true(report.complete, msg=sql)
      assert_eq(report.diagnostics.map(d => d.code), [
        "ML210",
        if suffix == "" {
          "ML212"
        } else {
          "ML211"
        },
        "ML214",
      ])
    }
  }
}

///|
test "foreign-key actions and explicit timing preserve their effects" {
  for action in ["NO ACTION", "RESTRICT", "CASCADE", "SET NULL", "SET DEFAULT"] {
    for order in ["DELETE", "UPDATE"] {
      for timing in ["", " NOT DEFERRABLE", " DEFERRABLE INITIALLY DEFERRED"] {
        let sql = "ALTER TABLE events ADD FOREIGN KEY (account_id) REFERENCES accounts MATCH SIMPLE ON " +
          order +
          " " +
          action +
          timing +
          " NOT VALID;"
        let report = @migration_lens.review_sql(
          sql,
          execution=ExistingTransaction,
        )
        assert_true(report.complete, msg=sql)
        assert_eq(
          report.diagnostics.any(d => d.code == "ML213"),
          action != "NO ACTION" && action != "RESTRICT",
        )
        assert_eq(
          report.diagnostics[2].help.contains("DEFERRABLE changes"),
          timing == " DEFERRABLE INITIALLY DEFERRED",
        )
      }
    }
  }
  let reversed = @migration_lens.review_sql(
    "ALTER TABLE events ADD FOREIGN KEY (a,b) REFERENCES accounts(x,y) MATCH FULL ON UPDATE CASCADE ON DELETE RESTRICT NOT VALID;",
    execution=SeparateStatements,
  )
  assert_true(reversed.complete)
  assert_true(reversed.diagnostics.any(d => d.code == "ML213"))
}

///|
test "foreign-key column lists consume every quoted identifier" {
  for count in 1..<=24 {
    let columns : Array[String] = []
    for i in 0..<count {
      columns.push("\"col;😀,\{i}\"")
    }
    let names = columns.join(",")
    let sql = "ALTER TABLE \"s;名\".\"表😀\" ADD FOREIGN KEY (" +
      names +
      ") REFERENCES \"父;表\"(" +
      names +
      ") NOT VALID;"
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_true(report.complete, msg=sql)
    assert_eq(report.statements, 1)
    assert_eq(
      @migration_lens.Report::parse_json(report.to_json().stringify()),
      Ok(report),
    )
  }
}

///|
test "foreign-key grammar rejects unmatched columns and unrepresented clauses" {
  for
    body in [
      "FOREIGN KEY () REFERENCES p(id)", "FOREIGN KEY (a,) REFERENCES p(id)", "FOREIGN KEY (a,b) REFERENCES p(id)",
      "FOREIGN KEY (a) REFERENCES db.public.p(id)", "FOREIGN KEY (a) REFERENCES p(id) MATCH PARTIAL",
      "FOREIGN KEY (a) REFERENCES p(id) NOT ENFORCED", "FOREIGN KEY (a) REFERENCES p(id) ON DELETE CASCADE ON DELETE RESTRICT",
      "FOREIGN KEY (a) REFERENCES p(id) ON UPDATE", "FOREIGN KEY (a) REFERENCES p(id) ON DELETE SET NULL (a)",
      "FOREIGN KEY (a) REFERENCES p(id) NOT VALID DEFERRABLE", "FOREIGN KEY (a) REFERENCES p(id), DROP COLUMN a",
      "FOREIGN KEY (a) REFERENCES p(id) NOT VALID NOT VALID", "FOREIGN KEY (a) REFERENCES p(id) INITIALLY DEFERRED",
      "FOREIGN KEY (a) REFERENCES p(id) DEFERRABLE NOT DEFERRABLE",
    ] {
    let report = @migration_lens.review_sql(
      "ALTER TABLE events ADD " + body + "; DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=body)
    assert_eq(report.diagnostics[0].code, "ML003", msg=body)
    assert_true(!report.diagnostics.any(d => d.code == "ML210"))
    assert_true(report.diagnostics.any(d => d.code == "ML102"))
  }
}

///|
test "foreign-key install validate and concurrent-index phases retain state" {
  let sql = "SET lock_timeout=100; ALTER TABLE events ADD CONSTRAINT fk FOREIGN KEY (account_id) REFERENCES accounts(id) NOT VALID; ALTER TABLE events VALIDATE CONSTRAINT fk; CREATE INDEX CONCURRENTLY child_idx ON events(account_id);"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), [
    "ML210", "ML211", "ML214", "ML180", "ML181",
  ])
  let simple = @migration_lens.review_sql(
    sql,
    execution=SimpleQuery,
    max_lock_timeout_ms=100,
  )
  assert_true(simple.diagnostics.any(d => d.code == "ML101"))
  let scoped_report = @migration_lens.review_sql(
    "BEGIN; SET LOCAL lock_timeout=100; ALTER TABLE events ADD FOREIGN KEY (a) REFERENCES accounts NOT VALID; ROLLBACK; DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
    initial_lock_timeout_ms=101,
  )
  assert_eq(scoped_report.diagnostics.map(d => d.code), [
    "ML210", "ML211", "ML214", "ML205",
  ])
}

///|
test "foreign-key errors retain uncertainty and source through all exports" {
  let sql = "-- 😀\r\nSELECT 1; ALTER TABLE \"表;😀\" ADD FOREIGN KEY (\"a,b\") REFERENCES p(id) ON DELETE CASCADE NOT VALID; DROP INDEX CONCURRENTLY a;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_eq(report.exit_code(), 2)
  assert_true(report.diagnostics.any(d => d.code == "ML102"))
  let warning = report.diagnostics.filter(d => d.code == "ML210")[0]
  assert_eq(
    report.source[warning.span.start:warning.span.end].to_owned(),
    "ALTER TABLE \"表;😀\" ADD FOREIGN KEY (\"a,b\") REFERENCES p(id) ON DELETE CASCADE NOT VALID;",
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
      require_lock_timeout=true,
    ).to_json(),
  )
  assert_true(report.to_sarif("migrations/foreign-key.sql") is Ok(_))
}
