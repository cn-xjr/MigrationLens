///|
test "constraint validation supports bounded names scope and action lists" {
  for prefix in ["", "IF EXISTS ", "ONLY ", "IF EXISTS ONLY "] {
    for target in ["events", "public.events", "\"s;名\".\"表😀\""] {
      let sql = "ALTER TABLE " +
        prefix +
        target +
        " VALIDATE CONSTRAINT \"c,名\", VALIDATE CONSTRAINT positive_id;"
      let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
      assert_true(report.complete, msg=sql)
      assert_eq(report.diagnostics.map(d => d.code), ["ML180", "ML181"])
    }
  }
  let expanded = @migration_lens.review_sql(
    "ALTER TABLE public.events* VALIDATE CONSTRAINT c;",
    execution=SeparateStatements,
  )
  assert_eq(expanded.diagnostics.map(d => d.code), ["ML180", "ML181"])
}

///|
test "constraint action lists consume every item including quoted delimiters" {
  for count in 1..<=32 {
    let actions : Array[String] = []
    for i in 0..<count {
      actions.push("VALIDATE CONSTRAINT \"check;😀,\{i}\"")
    }
    let sql = "ALTER TABLE events " + actions.join(", ") + ";"
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_true(report.complete, msg=sql)
    assert_eq(report.statements, 1)
    assert_eq(report.diagnostics.length(), 2)
    assert_eq(
      @migration_lens.Report::parse_json(report.to_json().stringify()),
      Ok(report),
    )
  }
}

///|
test "mixed ALTER TABLE actions never inherit validation's weaker lock" {
  for
    sql in [
      "ALTER TABLE events VALIDATE CONSTRAINT c, ADD COLUMN x integer", "ALTER TABLE events ADD COLUMN x integer, VALIDATE CONSTRAINT c",
      "ALTER TABLE events VALIDATE CONSTRAINT c, DROP CONSTRAINT other", "ALTER TABLE events VALIDATE CONSTRAINT c, VALIDATE CONSTRAINT d, SET LOGGED",
      "ALTER TABLE events VALIDATE CONSTRAINT c NOT VALID", "ALTER TABLE events VALIDATE CONSTRAINT c CASCADE",
    ] {
    let report = @migration_lens.review_sql(
      sql + "; DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_eq(report.diagnostics[0].code, "ML003")
    assert_true(!report.diagnostics.any(d => d.code == "ML180"))
    assert_true(report.diagnostics.any(d => d.code == "ML102"))
  }
}

///|
test "constraint validation rejects malformed names prefixes and lists" {
  for
    sql in [
      "ALTER TABLE", "ALTER TABLE events", "ALTER TABLE IF events VALIDATE CONSTRAINT c",
      "ALTER TABLE IF EXISTS VALIDATE CONSTRAINT c", "ALTER TABLE ONLY events* VALIDATE CONSTRAINT c",
      "ALTER TABLE db.public.events VALIDATE CONSTRAINT c", "ALTER TABLE events VALIDATE CONSTRAINT",
      "ALTER TABLE events VALIDATE CONSTRAINT s.c", "ALTER TABLE events VALIDATE CONSTRAINT c,",
      "ALTER TABLE events VALIDATE CONSTRAINT c,, VALIDATE CONSTRAINT d", "ALTER TABLE events VALIDATE CONSTRAINT c VALIDATE CONSTRAINT d",
      "ALTER TABLE events VALIDATE c", "ALTER TABLE events VALIDATE CONSTRAINT 'c'",
    ] {
    let report = @migration_lens.review_sql(
      sql + "; ANALYZE events;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_eq(report.diagnostics[0].code, "ML003", msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML140"))
  }
}

///|
test "validation preserves local timeout savepoint and downstream dispatch behavior" {
  let sql = "BEGIN; SET LOCAL lock_timeout=100; SAVEPOINT before_validate; ALTER TABLE events VALIDATE CONSTRAINT c; ROLLBACK TO before_validate; COMMIT; DROP INDEX CONCURRENTLY a;"
  let separate = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
    initial_lock_timeout_ms=100,
  )
  assert_true(separate.complete)
  assert_eq(separate.diagnostics.map(d => d.code), ["ML180", "ML181"])
  let simple = @migration_lens.review_sql(
    sql,
    execution=SimpleQuery,
    max_lock_timeout_ms=100,
    initial_lock_timeout_ms=100,
  )
  assert_true(simple.diagnostics.any(d => d.code == "ML101"))
  let too_long = @migration_lens.review_sql(
    "ALTER TABLE events VALIDATE CONSTRAINT c;",
    execution=ExistingTransaction,
    max_lock_timeout_ms=99,
    initial_lock_timeout_ms=100,
  )
  assert_eq(too_long.diagnostics.map(d => d.code), ["ML205", "ML180", "ML181"])
}

///|
test "validation cannot repair unknown state and preserves source on export" {
  let sql = "-- 😀\r\nSELECT 1; ALTER TABLE \"表;😀\" VALIDATE CONSTRAINT \"check,名\"; DROP INDEX CONCURRENTLY a;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_eq(report.exit_code(), 2)
  assert_true(report.diagnostics.any(d => d.code == "ML102"))
  let validation = report.diagnostics.filter(d => d.code == "ML180")[0]
  assert_eq(
    report.source[validation.span.start:validation.span.end].to_owned(),
    "ALTER TABLE \"表;😀\" VALIDATE CONSTRAINT \"check,名\";",
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
  assert_true(report.to_sarif("migrations/validate.sql") is Ok(_))
}
