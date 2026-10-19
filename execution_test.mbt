///|
test "initial transaction and dispatch are independent facts" {
  let source = "COMMIT; CREATE INDEX CONCURRENTLY a ON t (id);"
  let separate = @migration_lens.review_sql(
    source,
    execution=SeparateStatements,
    initial_transaction=true,
  )
  assert_eq(separate.diagnostics.length(), 1)
  assert_eq(separate.diagnostics[0].code, "ML105")
  let batched = @migration_lens.review_sql(
    source,
    execution=SimpleQuery,
    initial_transaction=true,
  )
  assert_eq(batched.diagnostics[0].code, "ML105")
  assert_eq(batched.diagnostics[1].code, "ML101")
  assert_eq(
    separate,
    @migration_lens.review_sql(source, execution=ExistingTransaction),
  )
}
