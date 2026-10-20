///|
test "same SQL has different results under separate and simple-query dispatch" {
  let sql = "CREATE INDEX CONCURRENTLY a ON t (id); CREATE INDEX CONCURRENTLY b ON t (id);"
  assert_eq(
    @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
    0,
  )
  let batched = @migration_lens.review_sql(sql, execution=SimpleQuery)
  assert_true(batched.complete)
  assert_eq(batched.diagnostics.filter(d => d.code == "ML101").length(), 2)
}

///|
test "explicit transaction promotion and COMMIT do not escape simple-query batch" {
  let sql = "BEGIN; COMMIT; CREATE INDEX CONCURRENTLY a ON t (id);"
  assert_eq(
    @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
    0,
  )
  assert_eq(
    @migration_lens.review_sql(sql, execution=SimpleQuery).diagnostics[0].code,
    "ML101",
  )
  let explicit = @migration_lens.review_sql(
    "START TRANSACTION; DROP INDEX CONCURRENTLY a; ROLLBACK;",
    execution=SeparateStatements,
  )
  assert_eq(explicit.diagnostics[0].code, "ML101")
}

///|
test "unknown state never silently recovers at COMMIT" {
  let report = @migration_lens.review_sql(
    "DO $$ BEGIN; END $$; COMMIT; DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
  )
  assert_eq(report.exit_code(), 2)
  assert_true(report.diagnostics.any(d => d.code == "ML102"))
  assert_true(
    @migration_lens.review_sql(
      "CREATE INDEX CONCURRENTLY a ON t (id); BEGIN;",
      execution=SeparateStatements,
    ).diagnostics.any(d => d.code == "ML103"),
  )
}

///|
test "no nested BEGIN and ending caller transaction are visible" {
  let report = @migration_lens.review_sql(
    "BEGIN; COMMIT;",
    execution=ExistingTransaction,
  )
  assert_eq(report.diagnostics[0].code, "ML104")
  assert_eq(report.diagnostics[1].code, "ML105")
  for
    sql in [
      "BEGIN READ SOMETHING;", "COMMIT AND MAYBE CHAIN;", "DROP INDEX a ON t;", "BEGIN SELECT 1",
    ] {
    assert_eq(
      @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
      2,
    )
  }
}
