///|
test "qualified quoted and multi-name drops retain PostgreSQL clauses" {
  for
    sql in [
      "DROP INDEX CONCURRENTLY IF EXISTS public.events_idx RESTRICT;", "DROP INDEX CONCURRENTLY \"schema;name\".\"index,one\";",
      "DROP INDEX CONCURRENTLY \"中文😀\";",
    ] {
    assert_eq(
      @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
      0,
    )
    assert_eq(
      @migration_lens.review_sql(sql, execution=ExistingTransaction).diagnostics[0].code,
      "ML101",
    )
  }
  let ordinary = @migration_lens.review_sql(
    "DROP INDEX IF EXISTS public.a, \"b,c\" CASCADE;",
    execution=SeparateStatements,
  )
  assert_true(ordinary.complete)
  assert_eq(ordinary.diagnostics[0].code, "ML100")
}

///|
test "concurrent multi-name and cascade drops fail explicitly" {
  for
    sql in [
      "DROP INDEX CONCURRENTLY a, b;", "DROP INDEX CONCURRENTLY IF EXISTS a CASCADE;",
    ] {
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_true(report.complete)
    assert_eq(report.exit_code(), 1)
    assert_eq(report.diagnostics[0].code, "ML107")
    assert_eq(report.source, sql)
    assert_eq(report.diagnostics[0].span.end, sql.length())
    let later = @migration_lens.review_sql(
      sql + " DROP INDEX CONCURRENTLY c;",
      execution=SeparateStatements,
    )
    assert_eq(later.exit_code(), 2)
    assert_eq(later.diagnostics[1].code, "ML102")
  }
}

///|
test "drop grammar never accepts a literal identifier or ignores a suffix" {
  for
    sql in [
      "DROP INDEX 'a';", "DROP INDEX \"\";", "DROP INDEX a,;", "DROP INDEX a..b;",
      "DROP INDEX a.b.c;", "DROP INDEX a ON t;", "DROP INDEX IF a;", "DROP INDEX a CASCADE RESTRICT;",
      "DROP INDEX CONCURRENTLY;", "DROP INDEX a unexpected;",
    ] {
    assert_eq(
      @migration_lens.review_sql(sql, execution=SeparateStatements).exit_code(),
      2,
      msg=sql,
    )
  }
  assert_eq(
    @migration_lens.review_sql(
      "DROP /*comment*/ INDEX CONCURRENTLY \"a\"\"b\";",
      execution=SeparateStatements,
    ).exit_code(),
    0,
  )
}
