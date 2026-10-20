///|
test "batch baselines pair paths across reorder and retain both source snapshots" {
  let a = @migration_lens.Migration::new(
    "a.sql",
    "DROP INDEX a;",
    execution=SeparateStatements,
  )
  let b = @migration_lens.Migration::new(
    "b.sql",
    "DROP INDEX b;",
    execution=SeparateStatements,
  )
  let c = @migration_lens.Migration::new(
    "c.sql",
    "DROP INDEX c;",
    execution=SeparateStatements,
  )
  let before = @migration_lens.review_migrations([a, b][:])
  let after = @migration_lens.review_migrations([b, c][:])
  let delta = @migration_lens.compare_batches(before, after).unwrap()
  assert_eq(delta.files.length(), 3)
  assert_eq(delta.files[0].baseline_index, Some(1))
  assert_eq(delta.files[0].current_index, Some(0))
  assert_eq(delta.files[0].retained, 1)
  assert_eq(delta.files[1].baseline_index, None)
  assert_eq(delta.files[1].introduced, after.files[1].report.diagnostics)
  assert_eq(delta.files[2].current_index, None)
  assert_eq(delta.files[2].resolved, before.files[0].report.diagnostics)
  assert_eq(delta.exit_code(), 1)
  assert_eq(delta.baseline.to_json(), before.to_json())
  assert_eq(delta.current.to_json(), after.to_json())
  assert_eq(@json.parse(delta.to_json().stringify()), delta.to_json())
  assert_eq(
    delta.to_json().stringify(),
    @migration_lens.compare_batches(before, after)
    .unwrap()
    .to_json()
    .stringify(),
  )
  assert_true(delta.to_text().contains("a.sql"))
  assert_true(delta.to_text().contains("c.sql"))
}

///|
test "matched batch files compare changed source and retain nullable integer provenance" {
  let before = @migration_lens.review_migrations(
    [
      @migration_lens.Migration::new(
        "a.sql",
        "DROP INDEX a;",
        execution=SeparateStatements,
      ),
    ][:],
  )
  let after = @migration_lens.review_migrations(
    [
      @migration_lens.Migration::new(
        "a.sql",
        "-- 😀\r\nDROP INDEX a; DROP INDEX b;",
        execution=SeparateStatements,
      ),
    ][:],
  )
  let delta = @migration_lens.compare_batches(before, after).unwrap()
  assert_eq(delta.files.length(), 1)
  assert_eq(delta.files[0].retained, 1)
  assert_eq(delta.files[0].introduced, [after.files[0].report.diagnostics[1]])
  assert_true(delta.files[0].resolved.is_empty())
  guard delta.to_json()
    is { "files": [{ "baseline_index": 0, "current_index": 0, .. }], .. } else {
    fail("indices must be plain integers")
  }
  let empty = @migration_lens.review_migrations([][:])
  guard @migration_lens.compare_batches(empty, after).unwrap().to_json()
    is { "files": [{ "baseline_index": Null, "current_index": 0, .. }], .. } else {
    fail("absent side must be null")
  }
}

///|
test "batch baseline duplicate paths pair by exact context and occurrence" {
  let ordinary = @migration_lens.Migration::new(
    "same.sql",
    "DROP INDEX a;",
    execution=SeparateStatements,
  )
  let wrapped = @migration_lens.Migration::new(
    "same.sql",
    "DROP INDEX a;",
    execution=ExistingTransaction,
  )
  let before = @migration_lens.review_migrations(
    [ordinary, wrapped, ordinary][:],
  )
  let after = @migration_lens.review_migrations(
    [wrapped, ordinary, ordinary, ordinary][:],
  )
  let delta = @migration_lens.compare_batches(before, after).unwrap()
  assert_eq(delta.files.length(), 4)
  for (i, old) in [(0, 1), (1, 0), (2, 2)] {
    assert_eq(delta.files[i].baseline_index, Some(old))
    assert_eq(delta.files[i].retained, 1)
  }
  assert_eq(delta.files[3].baseline_index, None)
  assert_eq(delta.files[3].introduced.length(), 1)
  let accepted = @migration_lens.compare_batches(before, before).unwrap()
  assert_eq(accepted.exit_code(), 0)
  assert_eq(accepted.current.exit_code(), 1)
}

///|
test "policy changes and shared entry facts never silently retain old findings" {
  let original = @migration_lens.Migration::new(
    "same.sql",
    "DROP INDEX a;",
    execution=SeparateStatements,
  )
  let before = @migration_lens.review_migrations([original][:])
  for
    changed in [
      @migration_lens.Migration::new(
        "renamed.sql",
        original.source,
        execution=SeparateStatements,
      ),
      @migration_lens.Migration::new(
        "same.sql",
        original.source,
        execution=SimpleQuery,
      ),
      @migration_lens.Migration::new(
        "same.sql",
        original.source,
        execution=SeparateStatements,
        initial_transaction=true,
      ),
      @migration_lens.Migration::new(
        "same.sql",
        original.source,
        execution=SeparateStatements,
        require_lock_timeout=true,
      ),
      @migration_lens.Migration::new(
        "same.sql",
        original.source,
        execution=SeparateStatements,
        max_lock_timeout_ms=100,
      ),
    ] {
    let after = @migration_lens.review_migrations([changed][:])
    let delta = @migration_lens.compare_batches(before, after).unwrap()
    assert_eq(delta.files.length(), 2)
    assert_eq(delta.files[0].baseline_index, None)
    assert_eq(delta.files[1].current_index, None)
    assert_eq(delta.files[0].retained, 0)
    assert_eq(delta.exit_code(), 1)
  }
  let known = @migration_lens.review_migrations(
    [original][:],
    initial_lock_timeout_ms=0,
  )
  assert_eq(
    @migration_lens.compare_batches(before, known).unwrap().files.length(),
    2,
  )
  assert_eq(
    @migration_lens.compare_batches(known, known).unwrap().files.length(),
    1,
  )
}

///|
test "batch baseline coverage is atomic and snapshots survive input mutation" {
  let good = @migration_lens.Migration::new(
    "a.sql",
    "DROP INDEX a;",
    execution=SeparateStatements,
  )
  let clean = @migration_lens.review_migrations([][:])
  let valid = @migration_lens.review_migrations([good][:])
  for
    bad in [
      @migration_lens.review_migrations(
        [
          good,
          @migration_lens.Migration::new(
            "b.sql",
            "SELECT 1;",
            execution=SeparateStatements,
          ),
        ][:],
      ),
      @migration_lens.review_migrations([good][:], initial_lock_timeout_ms=-1),
      @migration_lens.review_migrations([][:], initial_lock_timeout_ms=-1),
      @migration_lens.review_migrations(
        [@migration_lens.Migration::new("b.sql", "", execution=Unknown)][:],
      ),
      @migration_lens.review_migrations(
        [
          @migration_lens.Migration::new(
            "b.sql",
            "",
            execution=SeparateStatements,
            max_lock_timeout_ms=0,
          ),
        ][:],
      ),
      @migration_lens.review_migrations(
        [
          @migration_lens.Migration::new(
            "😀".unsafe_substring(start=0, end=1),
            "",
            execution=SeparateStatements,
          ),
        ][:],
      ),
    ] {
    assert_true(@migration_lens.compare_batches(bad, valid) is Err(_))
    assert_true(@migration_lens.compare_batches(valid, bad) is Err(_))
  }
  let delta = @migration_lens.compare_batches(clean, valid).unwrap()
  let saved = delta.to_json().stringify()
  valid.files[0].report.diagnostics.clear()
  valid.files.clear()
  assert_eq(delta.to_json().stringify(), saved)
  assert_eq(delta.current.files.length(), 1)
  assert_eq(
    @migration_lens.compare_batches(clean, clean).unwrap().exit_code(),
    0,
  )
}

///|
test "batch baseline duplicate distributions conserve every file and diagnostic" {
  let item = @migration_lens.Migration::new(
    "same.sql",
    "DROP INDEX a;",
    execution=SeparateStatements,
  )
  for left in 0..<=4 {
    for right in 0..<=4 {
      let old = []
      let new = []
      for _ in 0..<left {
        old.push(item)
      }
      for _ in 0..<right {
        new.push(item)
      }
      let delta = @migration_lens.compare_batches(
        @migration_lens.review_migrations(old[:]),
        @migration_lens.review_migrations(new[:]),
      ).unwrap()
      let mut introduced = 0
      let mut resolved = 0
      let mut retained = 0
      let old_indices : Array[Int32] = []
      let new_indices : Array[Int32] = []
      for file in delta.files {
        introduced += file.introduced.length()
        resolved += file.resolved.length()
        retained += file.retained
        if file.baseline_index is Some(i) {
          assert_true(!old_indices.contains(i))
          old_indices.push(i)
        }
        if file.current_index is Some(i) {
          assert_true(!new_indices.contains(i))
          new_indices.push(i)
        }
      }
      assert_eq(old_indices.length(), left)
      assert_eq(new_indices.length(), right)
      assert_eq(retained + introduced, right)
      assert_eq(retained + resolved, left)
      assert_eq(delta.exit_code(), if right > left { 1 } else { 0 })
    }
  }
}
