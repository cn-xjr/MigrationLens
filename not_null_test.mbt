///|
test "SET NOT NULL accepts explicit column keyword and table scope" {
  for prefix in ["", "IF EXISTS ", "ONLY ", "IF EXISTS ONLY "] {
    for keyword in ["", "COLUMN "] {
      let sql = "ALTER TABLE " +
        prefix +
        "\"s;名\".\"表😀\" ALTER " +
        keyword +
        "\"col,😀\" SET NOT NULL;"
      let report = @migration_lens.review_sql(
        sql,
        execution=ExistingTransaction,
      )
      assert_true(report.complete, msg=sql)
      assert_eq(report.diagnostics.map(d => d.code), ["ML220", "ML221"])
    }
  }
  let expanded = @migration_lens.review_sql(
    "ALTER TABLE public.events* ALTER COLUMN id SET NOT NULL;",
    execution=SeparateStatements,
  )
  assert_eq(expanded.diagnostics.map(d => d.code), ["ML220", "ML221"])
}

///|
test "SET NOT NULL action lists preserve every action and source" {
  for count in 1..<=32 {
    let actions : Array[String] = []
    for i in 0..<count {
      actions.push("ALTER COLUMN \"key;😀,\{i}\" SET NOT NULL")
    }
    let sql = "ALTER TABLE events " + actions.join(", ") + ";"
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_true(report.complete, msg=sql)
    assert_eq(report.statements, 1)
    assert_eq(report.diagnostics.length(), 2)
    assert_eq(
      report.source[report.diagnostics[0].span.start:report.diagnostics[0].span.end].to_owned(),
      sql,
    )
    assert_eq(
      @migration_lens.Report::parse_json(report.to_json().stringify()),
      Ok(report),
    )
  }
}

///|
test "mixed nullability actions cannot hide removal of a CHECK proof" {
  for
    action in [
      "ALTER COLUMN id SET NOT NULL, DROP CONSTRAINT nn_proof", "DROP CONSTRAINT nn_proof, ALTER COLUMN id SET NOT NULL",
      "ALTER COLUMN id SET NOT NULL, ALTER COLUMN other DROP NOT NULL", "ALTER COLUMN id SET NOT NULL, ADD COLUMN x integer",
      "ALTER COLUMN id SET NOT NULL NOT VALID", "ALTER COLUMN id SET NOT NULL NO INHERIT",
      "ALTER COLUMN id SET NOT NULL, VALIDATE CONSTRAINT nn_proof",
    ] {
    let report = @migration_lens.review_sql(
      "ALTER TABLE events " + action + "; DROP INDEX CONCURRENTLY old_idx;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=action)
    assert_eq(report.diagnostics[0].code, "ML003")
    assert_true(!report.diagnostics.any(d => d.code == "ML220"))
    assert_true(report.diagnostics.any(d => d.code == "ML102"))
  }
}

///|
test "SET NOT NULL rejects malformed actions at every boundary" {
  for
    action in [
      "ALTER", "ALTER COLUMN", "ALTER COLUMN id", "ALTER COLUMN id SET", "ALTER COLUMN id SET NOT",
      "ALTER COLUMN id SET NULL", "ALTER COLUMN s.id SET NOT NULL", "ALTER COLUMN 'id' SET NOT NULL",
      "ALTER COLUMN id SET NOT NULL,", "ALTER COLUMN id SET NOT NULL,, ALTER COLUMN x SET NOT NULL",
      "ALTER COLUMN id SET NOT NULL ALTER COLUMN x SET NOT NULL", "ALTER COLUMN IF EXISTS id SET NOT NULL",
    ] {
    let report = @migration_lens.review_sql(
      "ALTER TABLE events " + action + "; ANALYZE events;",
      execution=SeparateStatements,
    )
    assert_eq(report.exit_code(), 2, msg=action)
    assert_eq(report.diagnostics[0].code, "ML003", msg=action)
    assert_true(report.diagnostics.any(d => d.code == "ML140"))
  }
}

///|
test "validation nullability and index phases preserve dispatch and timeout policy" {
  let sql = "SET lock_timeout=100; ALTER TABLE events VALIDATE CONSTRAINT id_nn; ALTER TABLE events ALTER COLUMN id SET NOT NULL; CREATE UNIQUE INDEX CONCURRENTLY key_idx ON events(id); ALTER TABLE events ADD UNIQUE USING INDEX key_idx;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), [
    "ML180", "ML181", "ML220", "ML221", "ML190", "ML191",
  ])
  assert_true(
    report.diagnostics.filter(d => d.code == "ML221")[0].help.contains(
      "does not establish",
    ),
  )
  let simple = @migration_lens.review_sql(
    sql,
    execution=SimpleQuery,
    max_lock_timeout_ms=100,
  )
  assert_true(simple.diagnostics.any(d => d.code == "ML101"))
  let scoped_report = @migration_lens.review_sql(
    "BEGIN; SET LOCAL lock_timeout=100; SAVEPOINT s; ALTER TABLE events ALTER COLUMN id SET NOT NULL; ROLLBACK TO s; COMMIT; DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
    initial_lock_timeout_ms=101,
  )
  assert_eq(scoped_report.diagnostics.map(d => d.code), [
    "ML220", "ML221", "ML205",
  ])
}

///|
test "nullability review preserves uncertainty Unicode spans and deterministic exports" {
  let sql = "-- 😀\r\nSELECT 1; ALTER TABLE \"表;😀\" ALTER COLUMN \"id,名\" SET NOT NULL; DROP INDEX CONCURRENTLY a;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_eq(report.exit_code(), 2)
  assert_true(report.diagnostics.any(d => d.code == "ML102"))
  let warning = report.diagnostics.filter(d => d.code == "ML220")[0]
  assert_eq(
    report.source[warning.span.start:warning.span.end].to_owned(),
    "ALTER TABLE \"表;😀\" ALTER COLUMN \"id,名\" SET NOT NULL;",
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
  assert_true(report.to_sarif("migrations/not-null.sql") is Ok(_))
}
