///|
fn main raise {
  let archive = @lens.ReviewArchive::review(
    "orders-service",
    [
      @lens.Migration::new(
        "migrations/001.sql",
        "SET lock_timeout=100; CREATE UNIQUE INDEX CONCURRENTLY orders_key ON orders(external_key); ALTER TABLE orders ADD UNIQUE USING INDEX orders_key;",
        execution=SeparateStatements,
        max_lock_timeout_ms=100,
      ),
    ][:],
  ).unwrap()
  let report = archive.batch.files[0].report
  assert_eq(
    @lens.compare_archives(
      archive,
      @lens.ReviewArchive::parse_json(archive.to_json().stringify()).unwrap(),
    )
    .unwrap()
    .exit_code(),
    0,
  )
  assert_eq(report.diagnostics.map(d => d.code), ["ML190", "ML191"])
  println("MigrationLens downstream consumer: index rollout reviewed")
}
