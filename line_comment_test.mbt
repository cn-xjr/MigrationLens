///|
test "all PostgreSQL line endings terminate a line comment" {
  for ending in ["\n", "\r", "\r\n"] {
    let prefix = "-- migration comment 😀" + ending
    let sql = prefix + "DROP INDEX old_idx;"
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_true(report.complete)
    assert_eq(report.statements, 1, msg=ending)
    assert_eq(report.diagnostics.map(d => d.code), ["ML100"], msg=ending)
    assert_eq(report.diagnostics[0].span.start, prefix.length())
    assert_eq(report.source, sql)
  }
}

///|
test "CR-terminated comments cannot hide transaction or timeout changes" {
  let sql = "-- header\rSET lock_timeout=0; -- change applies next\rBEGIN; -- explicit block\rCREATE INDEX CONCURRENTLY idx ON events(id); COMMIT;"
  let report = @migration_lens.review_sql(
    sql,
    execution=SeparateStatements,
    require_lock_timeout=true,
  )
  assert_true(report.complete)
  assert_eq(report.statements, 4)
  assert_eq(report.diagnostics.map(d => d.code), ["ML201", "ML101"])
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
  assert_true(report.to_sarif("migrations/cr-lines.sql") is Ok(_))
}

///|
test "line-ending variants preserve findings while comment delimiters stay opaque" {
  for count in 1..<=16 {
    for ending in ["\n", "\r", "\r\n"] {
      let sql = StringBuilder()
      for i in 0..<count {
        sql.write_string("-- comment; \"quoted\" $$ ignored \{i}" + ending)
        sql.write_string("DROP INDEX \"idx--\{i}\";" + ending)
      }
      let source = sql.to_string()
      let report = @migration_lens.review_sql(
        source,
        execution=SeparateStatements,
      )
      assert_true(report.complete)
      assert_eq(report.statements, count)
      assert_eq(
        report.diagnostics.map(d => d.code),
        Array::make(count, "ML100"),
      )
      assert_eq(
        @migration_lens.Report::parse_json(report.to_json().stringify()),
        Ok(report),
      )
    }
  }
}

///|
test "inline comments and PostgreSQL whitespace preserve complete statements" {
  for ending in ["\n", "\r", "\r\n"] {
    let sql = "DROP -- opaque; BEGIN $$ \"\"" +
      ending +
      " INDEX old_idx; -- no final newline: DROP INDEX hidden;"
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_true(report.complete)
    assert_eq(report.statements, 1)
    assert_eq(report.diagnostics.map(d => d.code), ["ML100"])
    assert_eq(report.diagnostics[0].span.start, 0)
  }
  for separator in [" ", "\t", "\n", "\r", "\u000b", "\u000c"] {
    let sql = ["DROP", "INDEX", "old_idx;"].join(separator)
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    assert_true(report.complete, msg=separator)
    assert_eq(report.diagnostics.map(d => d.code), ["ML100"])
  }
}
