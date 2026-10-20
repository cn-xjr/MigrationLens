///|
test "all LOCK modes distinguish impact and default to ACCESS EXCLUSIVE" {
  for
    (mode, impact) in [
      ("ACCESS SHARE", "conflicts with ACCESS EXCLUSIVE"),
      ("ROW SHARE", "conflicts with EXCLUSIVE and ACCESS EXCLUSIVE"),
      ("ROW EXCLUSIVE", "allows ordinary concurrent writes"),
      ("SHARE UPDATE EXCLUSIVE", "concurrent maintenance"),
      ("SHARE", "block ordinary writes while allowing ordinary reads"),
      (
        "SHARE ROW EXCLUSIVE", "block ordinary writes while allowing ordinary reads",
      ),
      ("EXCLUSIVE", "locking reads while allowing ordinary non-locking reads"),
      ("ACCESS EXCLUSIVE", "block ordinary reads and writes"),
    ] {
    let report = @migration_lens.review_sql(
      "LOCK TABLE t IN " + mode + " MODE;",
      execution=ExistingTransaction,
    )
    assert_true(report.complete, msg=mode)
    assert_eq(report.diagnostics.length(), 1, msg=mode)
    assert_eq(report.diagnostics[0].code, "ML120")
    assert_true(report.diagnostics[0].message.contains(mode))
    assert_true(report.diagnostics[0].message.contains(impact))
  }
  let default = @migration_lens.review_sql(
    "LOCK t;",
    execution=ExistingTransaction,
  )
  assert_true(default.diagnostics[0].message.contains("ACCESS EXCLUSIVE"))
  for
    sql in [
      "LOCK t.NOWAIT;", "LOCK t, NOWAIT;", "LOCK \"NOWAIT\";", "LOCK ONLY t, u* NOWAIT;",
    ] {
    let named = @migration_lens.review_sql(sql, execution=ExistingTransaction)
    assert_true(named.complete, msg=sql)
    assert_eq(named.diagnostics.length(), 1)
    assert_true(named.diagnostics[0].message.contains("ACCESS EXCLUSIVE"))
  }
}

///|
test "LOCK requires a block and accepts implicit simple-query transactions" {
  for execution in [@migration_lens.SeparateStatements, SimpleQuery] {
    let idle = @migration_lens.review_sql("LOCK TABLE t;", execution~)
    assert_eq(idle.exit_code(), 1)
    assert_eq(idle.diagnostics[0].code, "ML121")
    assert_eq(idle.diagnostics[0].severity, Error)
  }
  for
    sql in [
      "SET lock_timeout=100; LOCK t;", "LOCK t; SET lock_timeout=100;", "BEGIN; COMMIT; LOCK t;",
    ] {
    let report = @migration_lens.review_sql(sql, execution=SimpleQuery)
    assert_true(report.complete)
    assert_true(!report.diagnostics.any(d => d.code == "ML121"))
  }
  for (sql, initial) in [("LOCK t;", true), ("BEGIN; LOCK t; COMMIT;", false)] {
    let report = @migration_lens.review_sql(
      sql,
      execution=SeparateStatements,
      initial_transaction=initial,
    )
    assert_eq(report.diagnostics.length(), 1)
    assert_eq(report.diagnostics[0].code, "ML120")
  }
  let uncertain = @migration_lens.review_sql("LOCK t;", execution=Unknown)
  assert_eq(uncertain.exit_code(), 2)
  assert_true(
    uncertain.diagnostics.any(d => d.code == "ML121" && d.severity == Incomplete),
  )
}

///|
test "NOWAIT bypasses only its acquisition timeout policy and retains impact" {
  let blocked = @migration_lens.review_sql(
    "LOCK t IN SHARE MODE;",
    execution=ExistingTransaction,
    max_lock_timeout_ms=100,
    initial_lock_timeout_ms=200,
  )
  assert_eq(blocked.diagnostics[0].code, "ML205")
  for initial in [0, 200] {
    let report = @migration_lens.review_sql(
      "LOCK t IN SHARE MODE NOWAIT;",
      execution=ExistingTransaction,
      max_lock_timeout_ms=100,
      initial_lock_timeout_ms=initial,
    )
    assert_eq(report.diagnostics.length(), 1)
    assert_eq(report.diagnostics[0].code, "ML120")
    assert_true(
      report.diagnostics[0].help.contains("does not shorten lock lifetime"),
    )
  }
  let later = @migration_lens.review_sql(
    "BEGIN; LOCK t NOWAIT; CREATE INDEX a ON t(id); COMMIT;",
    execution=SeparateStatements,
    require_lock_timeout=true,
    initial_lock_timeout_ms=0,
  )
  assert_eq(later.diagnostics.filter(d => d.code == "ML201").length(), 1)
  let scoped = @migration_lens.review_sql(
    "BEGIN; SET LOCAL lock_timeout=100; LOCK t; SAVEPOINT a; SET LOCAL lock_timeout=0; ROLLBACK TO a; LOCK t; COMMIT;",
    execution=SeparateStatements,
    max_lock_timeout_ms=100,
  )
  assert_true(scoped.complete)
  assert_eq(scoped.diagnostics.length(), 2)
  assert_true(scoped.diagnostics.all(d => d.code == "ML120"))
  for (initial, code) in [(0, "ML201"), (100, "ML120")] {
    let known = @migration_lens.review_sql(
      "LOCK t;",
      execution=ExistingTransaction,
      require_lock_timeout=true,
      initial_lock_timeout_ms=initial,
    )
    assert_eq(known.diagnostics[0].code, code)
  }
  let unknown = @migration_lens.review_sql(
    "LOCK t;",
    execution=ExistingTransaction,
    require_lock_timeout=true,
  )
  assert_eq(unknown.diagnostics[0].code, "ML202")
}

///|
test "LOCK relation lists preserve quoted delimiters Unicode comments and stable spans" {
  let sql = "-- 😀\r\nLOCK /* one /* nested */ */ TABLE ONLY public.\"a;b\", \"中文😀\"*, \"q\"\"name\" IN SHARE UPDATE EXCLUSIVE MODE NOWAIT;"
  let report = @migration_lens.review_sql(sql, execution=ExistingTransaction)
  assert_true(report.complete)
  assert_eq(report.statements, 1)
  assert_eq(report.diagnostics.length(), 1)
  assert_eq(report.diagnostics[0].span.start, 7)
  assert_eq(report.diagnostics[0].span.end, sql.length())
  assert_eq(report.source, sql)
  assert_eq(
    report,
    @migration_lens.review_sql(sql, execution=ExistingTransaction),
  )
  assert_eq(
    @migration_lens.Report::parse_json(report.to_json().stringify()).unwrap(),
    report,
  )
  assert_true(report.to_sarif("migrations/lock.sql") is Ok(_))
}

///|
test "unsupported LOCK syntax never loses clauses or restores downstream certainty" {
  for
    sql in [
      "LOCK;", "LOCK TABLE;", "LOCK TABLE ONLY;", "LOCK t,;", "LOCK t,,u;", "LOCK t.u.v;",
      "LOCK t IN SHARE;", "LOCK t IN UPDATE MODE;", "LOCK t IN SHARE MODE NOWAIT NOWAIT;",
      "LOCK t NOWAIT IN SHARE MODE;", "LOCK ONLY t*;", "LOCK ONLY (t);", "LOCK 't';",
      "LOCK \"\";", "LOCK t SKIP LOCKED;", "LOCK t IN SHARE MODE CASCADE;", "LOCK t PARTITION (p);",
      "LOCK TABLE t.*;", "LOCK TABLE t..u;",
    ] {
    let report = @migration_lens.review_sql(
      sql + " COMMIT; DROP INDEX CONCURRENTLY a;",
      execution=ExistingTransaction,
    )
    assert_eq(report.exit_code(), 2, msg=sql)
    assert_eq(report.diagnostics[0].code, "ML003", msg=sql)
    assert_true(report.diagnostics.any(d => d.code == "ML102"), msg=sql)
  }
  let failed = @migration_lens.review_sql(
    "LOCK t; DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
  )
  assert_eq(failed.exit_code(), 2)
  assert_true(failed.diagnostics.any(d => d.code == "ML102"))
  let recovered = @migration_lens.review_sql(
    "BEGIN; LOCK t; COMMIT; DROP INDEX CONCURRENTLY a;",
    execution=SeparateStatements,
  )
  assert_true(recovered.complete)
  assert_eq(recovered.diagnostics.length(), 1)
}
