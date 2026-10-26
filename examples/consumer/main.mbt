///|
fn main raise {
  let report = @lens.review_sql(
    "SET lock_timeout=100; CREATE UNIQUE INDEX CONCURRENTLY orders_key ON orders(external_key); ALTER TABLE orders ADD UNIQUE USING INDEX orders_key;",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_eq(report.diagnostics.map(d => d.code), ["ML190", "ML191"])
  println("MigrationLens downstream consumer: index rollout reviewed")
}
