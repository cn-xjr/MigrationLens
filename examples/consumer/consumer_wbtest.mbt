///|
test "a runner must declare whole-file dispatch independently from transactions" {
  let sql = "SET lock_timeout=100; CREATE INDEX CONCURRENTLY orders_idx ON orders(id);"
  let separate = @lens.review_sql(
    sql,
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  let whole_file = @lens.review_sql(
    sql,
    execution=SimpleQuery,
    max_lock_timeout_ms=100,
  )
  assert_eq(separate.exit_code(), 0)
  assert_eq(whole_file.exit_code(), 1)
  assert_eq(whole_file.diagnostics[0].code, "ML101")
  assert_eq(
    @lens.Report::parse_json(whole_file.to_json().stringify()),
    Ok(whole_file),
  )
}

///|
test "a tool reviews staged constraints without inventing catalog facts" {
  let report = @lens.review_sql(
    "SET lock_timeout=100; ALTER TABLE orders ADD CONSTRAINT orders_account_fk FOREIGN KEY(account_id) REFERENCES accounts(id) NOT VALID; ALTER TABLE orders VALIDATE CONSTRAINT orders_account_fk;",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(report.complete)
  assert_eq(report.diagnostics.map(d => d.code), [
    "ML210", "ML211", "ML214", "ML180", "ML181",
  ])
  assert_eq(report.exit_code(), 1)
  assert_true(report.to_sarif("migrations/constraints.sql") is Ok(_))
}

///|
test "a CI consumer restores batch archives and gates only newly introduced findings" {
  let accepted = @lens.review_migrations(
    [
      @lens.Migration::new(
        "migrations/001.sql",
        "DROP INDEX old_idx;",
        execution=SeparateStatements,
      ),
    ][:],
  )
  let current = @lens.review_migrations(
    [
      @lens.Migration::new(
        "migrations/001.sql",
        "DROP INDEX old_idx; DROP INDEX other_idx;",
        execution=SeparateStatements,
      ),
    ][:],
  )
  let baseline = @lens.BatchReport::parse_json(accepted.to_json().stringify()).unwrap()
  let restored = @lens.BatchReport::parse_json(current.to_json().stringify()).unwrap()
  let delta = @lens.compare_batches(baseline, restored).unwrap()
  assert_eq(delta.exit_code(), 1)
  assert_eq(delta.files[0].retained, 1)
  assert_eq(delta.files[0].introduced.length(), 1)
  assert_eq(@lens.compare_batches(restored, restored).unwrap().exit_code(), 0)
  assert_true(restored.to_sarif() is Ok(_))
}
