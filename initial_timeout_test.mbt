///|
fn initial_review(sql : String, value : Int32) -> @migration_lens.Report {
  @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    require_lock_timeout=true,
    initial_lock_timeout_ms=value,
  )
}

///|
test "initial timeout is an explicit fact rather than an implicit policy switch" {
  let sql = "DROP INDEX CONCURRENTLY a;"
  assert_eq(initial_review(sql, 100).exit_code(), 0)
  assert_eq(initial_review(sql, 0).diagnostics[0].code, "ML201")
  assert_eq(
    @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      initial_lock_timeout_ms=0,
    ).exit_code(),
    0,
  )
  assert_eq(
    @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      require_lock_timeout=true,
    ).diagnostics[0].code,
    "ML202",
  )
  assert_eq(
    @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      max_lock_timeout_ms=99,
      initial_lock_timeout_ms=100,
    ).diagnostics[0].code,
    "ML205",
  )
  assert_eq(initial_review(sql, 2147483647).exit_code(), 0)
  let invalid = initial_review(sql, -1)
  assert_eq(invalid.exit_code(), 2)
  assert_eq(invalid.statements, 0)
  assert_eq(invalid.source, sql)
  assert_eq(invalid.diagnostics[0].code, "ML012")
}

///|
test "initial timeout participates in rollback commit savepoint and chain scopes" {
  for
    control in [
      "BEGIN; SET lock_timeout=0; ROLLBACK;", "BEGIN; SET LOCAL lock_timeout=0; COMMIT;",
      "BEGIN; SAVEPOINT a; SET lock_timeout=0; ROLLBACK TO a; COMMIT;", "BEGIN; SET LOCAL lock_timeout=0; COMMIT AND CHAIN; ROLLBACK;",
    ] {
    assert_eq(
      initial_review(control + " DROP INDEX CONCURRENTLY a;", 100).exit_code(),
      0,
    )
  }
  for reset in ["RESET lock_timeout;", "SET lock_timeout=DEFAULT;"] {
    assert_eq(
      initial_review(reset + " DROP INDEX CONCURRENTLY a;", 100).diagnostics[0].code,
      "ML202",
    )
  }
  assert_eq(
    initial_review("SELECT 1; DROP INDEX CONCURRENTLY a;", 100).exit_code(),
    2,
  )
  assert_eq(
    initial_review("DROP INDEX CONCURRENTLY a;", 0).diagnostics[0].code,
    "ML201",
  )
  assert_eq(initial_review("DROP INDEX CONCURRENTLY a;", 100).exit_code(), 0)
}

///|
test "external rollback cannot infer the pre-transaction timeout baseline" {
  for control in ["ROLLBACK;", "ROLLBACK AND CHAIN; COMMIT;"] {
    let report = @migration_lens.review_sql(
      control + " DROP INDEX CONCURRENTLY a;",
      execution=ExistingTransaction,
      require_lock_timeout=true,
      initial_lock_timeout_ms=100,
    )
    assert_true(report.diagnostics.any(d => d.code == "ML202"))
    assert_eq(report.diagnostics[0].code, "ML105")
  }
  let committed = @migration_lens.review_sql(
    "COMMIT; DROP INDEX CONCURRENTLY a;",
    execution=ExistingTransaction,
    require_lock_timeout=true,
    initial_lock_timeout_ms=100,
  )
  assert_eq(committed.diagnostics.length(), 1)
  assert_eq(committed.diagnostics[0].code, "ML105")
  assert_eq(
    @migration_lens.review_sql(
      "DROP INDEX CONCURRENTLY a;",
      execution=Unknown,
      initial_lock_timeout_ms=100,
    ).exit_code(),
    2,
  )
}

///|
test "batch uses a fresh initial value for every input and records the fact" {
  let inputs = [
    @migration_lens.Migration::new(
      "a.sql",
      "SET lock_timeout=0; DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
      require_lock_timeout=true,
    ),
    @migration_lens.Migration::new(
      "b.sql",
      "DROP INDEX CONCURRENTLY b;",
      execution=SeparateStatements,
      require_lock_timeout=true,
    ),
  ]
  let batch = @migration_lens.review_migrations(
    inputs[:],
    initial_lock_timeout_ms=100,
  )
  assert_eq(batch.exit_code(), 1)
  assert_eq(batch.files[0].report.diagnostics[0].code, "ML201")
  assert_eq(batch.files[1].report.exit_code(), 0)
  assert_eq(batch.initial_lock_timeout_ms, Some(100))
  assert_eq(@json.parse(batch.to_json().stringify()), batch.to_json())
  assert_eq(
    batch.to_sarif().unwrap().stringify(),
    batch.to_sarif().unwrap().stringify(),
  )
  guard batch.to_json()
    is {
      "initial_lock_timeout_ms": 100,
      "files": [_, { "context": { "initial_lock_timeout_ms": 100, .. }, .. }],
      ..
    } else {
    fail("initial fact missing from JSON")
  }
  guard batch.to_sarif().unwrap()
    is {
      "runs": [
        _,
        {
          "properties": {
            "migrationLensContext": { "initial_lock_timeout_ms": 100, .. },
            ..
          },
          ..
        },
      ],
      ..
    } else {
    fail("initial fact missing from SARIF")
  }
  let bad = @migration_lens.review_migrations(
    inputs[:],
    initial_lock_timeout_ms=-1,
  )
  assert_eq(bad.exit_code(), 2)
  assert_eq(bad.files[0].report.diagnostics[0].code, "ML012")
  let empty = @migration_lens.review_migrations(
    [][:],
    initial_lock_timeout_ms=-1,
  )
  assert_eq(empty.exit_code(), 2)
  assert_true(empty.to_sarif() is Err(_))
  assert_true(empty.to_text().contains("must be nonnegative"))
  assert_true(
    !@migration_lens.review_migrations(inputs[:])
    .to_json()
    .stringify()
    .contains("initial_lock_timeout_ms"),
  )
}
