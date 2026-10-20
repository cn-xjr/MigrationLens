///|
test "batch reviews every migration without sharing transactions or settings" {
  let inputs = [
    @migration_lens.Migration::new(
      "a.sql",
      "BEGIN; SET LOCAL lock_timeout=100;",
      execution=SeparateStatements,
    ),
    @migration_lens.Migration::new(
      "b.sql",
      "DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
      require_lock_timeout=true,
    ),
    @migration_lens.Migration::new(
      "c.sql",
      "SELECT 1;",
      execution=SeparateStatements,
    ),
    @migration_lens.Migration::new(
      "d.sql",
      "DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    ),
  ]
  let report = @migration_lens.review_migrations(inputs[:])
  assert_eq(report.files.length(), 4)
  assert_eq(report.files[1].report.diagnostics[0].code, "ML202")
  assert_eq(report.files[3].report.exit_code(), 0)
  assert_eq(report.exit_code(), 2)
  assert_eq(report.files[0].migration.path, "a.sql")
  assert_eq(report.files[2].report.source, "SELECT 1;")
  assert_true(report.to_text().contains("== c.sql =="))
  assert_eq(@json.parse(report.to_json().stringify()), report.to_json())
  assert_eq(
    report.to_json().stringify(),
    @migration_lens.review_migrations(inputs[:]).to_json().stringify(),
  )
  guard report.to_json() is { "files": [_, { "context": context, .. }, ..], .. } else {
    fail("file context lost")
  }
  assert_eq(context, {
    "path": "b.sql",
    "execution": Json(@migration_lens.SeparateStatements),
    "initial_transaction": false,
    "require_lock_timeout": true,
    "max_lock_timeout_ms": Json::null(),
  })
}

///|
test "batch aggregate severity and per-file policies preserve existing behavior" {
  let clean = @migration_lens.Migration::new(
    "same.sql",
    "DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
  )
  assert_eq(@migration_lens.review_migrations([clean][:]).exit_code(), 0)
  let wrapped = @migration_lens.Migration::new(
    "same.sql",
    clean.source,
    execution=SimpleQuery,
    initial_transaction=true,
  )
  assert_eq(
    @migration_lens.review_migrations([clean, wrapped][:]).exit_code(),
    1,
  )
  let invalid = @migration_lens.Migration::new(
    "invalid.sql",
    clean.source,
    execution=SeparateStatements,
    max_lock_timeout_ms=0,
  )
  let report = @migration_lens.review_migrations([clean, invalid, clean][:])
  assert_eq(report.files.length(), 3)
  assert_eq(report.files[1].report.diagnostics[0].code, "ML011")
  assert_eq(report.files[2].report.exit_code(), 0)
  assert_eq(report.exit_code(), 2)
  assert_eq(@migration_lens.review_migrations([][:]).exit_code(), 0)
}

///|
test "batch SARIF preserves separate runs and refuses a partial export" {
  let inputs = [
    @migration_lens.Migration::new(
      "same.sql",
      "DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    ),
    @migration_lens.Migration::new(
      "same.sql",
      "SELECT 1;",
      execution=SeparateStatements,
    ),
  ]
  let report = @migration_lens.review_migrations(inputs[:])
  let data = report.to_sarif().unwrap()
  guard data is { "runs": [first, second], .. } else {
    fail("expected two separate SARIF runs")
  }
  guard first is { "invocations": [{ "executionSuccessful": true, .. }], .. } else {
    fail("clean run lost")
  }
  guard second is { "invocations": [{ "executionSuccessful": false, .. }], .. } else {
    fail("incomplete run lost")
  }
  assert_eq(@json.parse(data.stringify()), data)
  guard second is { "properties": { "migrationLensContext": context, .. }, .. } else {
    fail("SARIF context lost")
  }
  assert_eq(context, {
    "path": "same.sql",
    "execution": Json(@migration_lens.SeparateStatements),
    "initial_transaction": false,
    "require_lock_timeout": false,
    "max_lock_timeout_ms": Json::null(),
  })
  assert_eq(data.stringify(), report.to_sarif().unwrap().stringify())
  let bad = @migration_lens.review_migrations(
    [
      inputs[0],
      @migration_lens.Migration::new(
        "../bad.sql",
        "",
        execution=SeparateStatements,
      ),
    ][:],
  )
  assert_true(bad.to_sarif() is Err(_))
  assert_true(report.to_sarif() is Ok(_))
}
