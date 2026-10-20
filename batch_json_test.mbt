///|
test "batch artifact round trips retain sources contexts duplicates and failures" {
  let inputs = [
    @migration_lens.Migration::new(
      "同名😀.sql",
      "-- 😀\r\nDROP INDEX a;",
      execution=SeparateStatements,
      max_lock_timeout_ms=100,
    ),
    @migration_lens.Migration::new(
      "同名😀.sql",
      "SELECT 1;",
      execution=Unknown,
      initial_transaction=true,
      require_lock_timeout=true,
    ),
    @migration_lens.Migration::new(
      "other.sql",
      "DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
      max_lock_timeout_ms=-2147483648,
    ),
  ]
  for
    batch in [
      @migration_lens.review_migrations(inputs[:]),
      @migration_lens.review_migrations(
        inputs[:],
        initial_lock_timeout_ms=2147483647,
      ),
      @migration_lens.review_migrations(
        inputs[:],
        initial_lock_timeout_ms=-2147483648,
      ),
      @migration_lens.review_migrations([][:]),
      @migration_lens.review_migrations([][:], initial_lock_timeout_ms=-1),
    ] {
    let saved = batch.to_json().stringify()
    let restored = match @migration_lens.BatchReport::parse_json(saved) {
      Ok(b) => b
      Err(e) => fail(e + "\n" + saved)
    }
    assert_eq(restored.to_json().stringify(), saved)
    assert_eq(restored.to_text(), batch.to_text())
    assert_eq(restored.exit_code(), batch.exit_code())
    assert_eq(restored.initial_lock_timeout_ms, batch.initial_lock_timeout_ms)
    for i, file in restored.files {
      assert_eq(file.report, batch.files[i].report)
      assert_eq(file.migration.source, batch.files[i].migration.source)
      assert_eq(file.migration.path, batch.files[i].migration.path)
    }
  }
}

///|
test "batch decoder rejects unsupported root fields numeric forms and duplicate keys" {
  let good = @migration_lens.review_migrations([][:], initial_lock_timeout_ms=0)
    .to_json()
    .stringify()
  for
    bad in [
      "{}",
      "[]",
      "{",
      good.replace(old="\"format_version\":1", new="\"format_version\":2"),
      good.replace(old="\"exit_code\":0", new="\"exit_code\":1"),
      good.replace(old="\"exit_code\":0", new="\"exit_code\":0,\"extra\":1"),
      good.replace(old="\"exit_code\":0", new="\"exit_code\":0,\"exit_code\":0"),
      good.replace(
        old="\"exit_code\":0",
        new="\"exit_code\":0,\"exit_\\u0063ode\":0",
      ),
    ] {
    assert_true(@migration_lens.BatchReport::parse_json(bad) is Err(_), msg=bad)
  }
  for
    n in [
      "-0", "0.0", "1e0", "1.00000000000000001", "-2147483649", "2147483648", "null",
      "true",
    ] {
    let bad = good.replace(
      old="\"initial_lock_timeout_ms\":0",
      new="\"initial_lock_timeout_ms\":" + n,
    )
    assert_true(@migration_lens.BatchReport::parse_json(bad) is Err(_), msg=n)
  }
  assert_true(@migration_lens.BatchReport::parse_json(good) is Ok(_))
}

///|
test "batch decoder checks context snapshots nested metadata and configuration errors" {
  let input = @migration_lens.Migration::new(
    "a.sql",
    "DROP INDEX a;",
    execution=SeparateStatements,
    max_lock_timeout_ms=10,
  )
  let good = @migration_lens.review_migrations(
      [input][:],
      initial_lock_timeout_ms=100,
    )
    .to_json()
    .stringify()
  for
    (old, replacement) in [
      ("\"execution\":\"SeparateStatements\"", "\"execution\":\"Other\""),
      ("\"execution\":\"SeparateStatements\"", "\"execution\":\"Unknown\""),
      ("\"initial_transaction\":false", "\"initial_transaction\":0"),
      (
        "\"max_lock_timeout_ms\":[10]", "\"max_lock_timeout_ms\":[10.00000000000000001]",
      ),
      ("\"max_lock_timeout_ms\":[10]", "\"max_lock_timeout_ms\":[0]"),
      (
        "\"require_lock_timeout\":false", "\"require_lock_timeout\":false,\"extra\":1",
      ),
      ("\"start\":0", "\"start\":-1"),
      ("\"severity\":\"Warning\"", "\"severity\":\"Incomplete\""),
      ("\"code\":\"ML205\"", "\"code\":\"ML205\",\"code\":\"ML205\""),
    ] {
    let bad = good.replace(old~, new=replacement)
    assert_true(bad != good, msg=old)
    assert_true(@migration_lens.BatchReport::parse_json(bad) is Err(_), msg=old)
  }
  let mismatched = good.replace(
    old="\"context\":{\"path\":\"a.sql\"",
    new="\"context\":{\"path\":\"b.sql\"",
  )
  assert_true(@migration_lens.BatchReport::parse_json(mismatched) is Err(_))
  let invalid = @migration_lens.review_migrations(
      [][:],
      initial_lock_timeout_ms=-1,
    )
    .to_json()
    .stringify()
  assert_true(
    @migration_lens.BatchReport::parse_json(
      invalid.replace(old="must be nonnegative", new="changed"),
    )
    is Err(_),
  )
}

///|
test "restored batches export every SARIF run or reject the whole export" {
  let entries = [
    @migration_lens.Migration::new(
      "m/😀.sql",
      "DROP INDEX a;",
      execution=SeparateStatements,
    ),
    @migration_lens.Migration::new(
      "m/😀.sql",
      "SELECT 1;",
      execution=SeparateStatements,
    ),
  ]
  let original = @migration_lens.review_migrations(entries[:])
  let loaded = @migration_lens.BatchReport::parse_json(
    original.to_json().stringify(),
  ).unwrap()
  assert_eq(
    loaded.to_sarif().unwrap().stringify(),
    original.to_sarif().unwrap().stringify(),
  )
  let bad = @migration_lens.review_migrations(
    [
      @migration_lens.Migration::new(
        "../bad.sql",
        "",
        execution=SeparateStatements,
      ),
    ][:],
  )
  let loaded = @migration_lens.BatchReport::parse_json(
    bad.to_json().stringify(),
  ).unwrap()
  assert_eq(loaded.files[0].migration.path, "../bad.sql")
  assert_true(loaded.to_sarif() is Err(_))
}
