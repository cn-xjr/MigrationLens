///|
fn archive_for(
  sql : String,
  execution~ : @migration_lens.Execution = SeparateStatements,
  initial_transaction~ : Bool = false,
  require_lock_timeout~ : Bool = false,
  max_lock_timeout_ms? : Int32,
  initial_lock_timeout_ms? : Int32,
) -> @migration_lens.ReviewArchive {
  @migration_lens.ReviewArchive::review(
    "orders-service",
    [
      @migration_lens.Migration::new(
        "migrations/001.sql",
        sql,
        execution~,
        initial_transaction~,
        require_lock_timeout~,
        max_lock_timeout_ms?,
      ),
    ][:],
    initial_lock_timeout_ms?,
  ).unwrap()
}

///|
test "v2 preserves source complete and incomplete reports every context and deterministic rendering" {
  for
    sql in [
      "",
      "-- 😀\rDROP INDEX a;",
      "SELECT 1; DROP INDEX a;",
      "SELECT 'unterminated",
      "-- \u0000",
      "x".repeat(1000001),
    ] {
    for
      execution in [
        @migration_lens.SeparateStatements,
        SimpleQuery,
        ExistingTransaction,
        Unknown,
      ] {
      let original = archive_for(
        sql,
        execution~,
        initial_transaction=true,
        require_lock_timeout=true,
        max_lock_timeout_ms=100,
        initial_lock_timeout_ms=50,
      )
      let text = original.to_json().stringify()
      let restored = @migration_lens.ReviewArchive::parse_json(text).unwrap()
      assert_eq(restored.to_json().stringify(), text)
      assert_eq(restored.to_text(), original.to_text())
      assert_eq(restored.exit_code(), original.exit_code())
      assert_eq(restored.batch.files[0].report.source, sql)
      assert_eq(restored.origin.project, "orders-service")
      assert_eq(restored.origin.database, "postgresql-18")
    }
  }
}

///|
test "v2 rejects every origin mismatch while retaining unknown versions for viewing" {
  let original = archive_for("DROP INDEX a;")
  for key in ["project", "tool_version", "rules_version", "database"] {
    let data = original.to_json()
    guard data is { "origin": Object(origin), .. } else { fail("origin") }
    origin[key] = Json("different")
    let restored = @migration_lens.ReviewArchive::parse_json(data.stringify()).unwrap()
    assert_eq(restored.to_json(), data)
    assert_true(@migration_lens.compare_archives(original, restored) is Err(_))
    if key == "database" {
      assert_true(
        @migration_lens.compare_archives(restored, restored) is Err(_),
      )
    }
  }
}

///|
test "checked comparison refuses changed dispatch transaction and timeout settings" {
  let baseline = archive_for("DROP INDEX a;")
  for
    current in [
      archive_for("DROP INDEX a;", execution=SimpleQuery),
      archive_for("DROP INDEX a;", initial_transaction=true),
      archive_for("DROP INDEX a;", require_lock_timeout=true),
      archive_for("DROP INDEX a;", max_lock_timeout_ms=100),
      archive_for("DROP INDEX a;", initial_lock_timeout_ms=100),
      archive_for("DROP INDEX a;", execution=Unknown),
    ] {
    assert_true(@migration_lens.compare_archives(baseline, current) is Err(_))
  }
  let known = archive_for("DROP INDEX a;", initial_lock_timeout_ms=100)
  assert_true(
    @migration_lens.compare_archives(
      known,
      archive_for("DROP INDEX a;", initial_lock_timeout_ms=101),
    )
    is Err(_),
  )
}

///|
test "v2 schema is strict and never upgrades legacy input by inventing provenance" {
  let original = archive_for("DROP INDEX a;")
  for
    bad in [
      "{}",
      "[]",
      "{",
      original.batch.to_json().stringify(),
      original.batch.files[0].report.to_json().stringify(),
    ] {
    assert_true(@migration_lens.ReviewArchive::parse_json(bad) is Err(_))
  }
  for version in ["1", "3", "2.0", "2e0", "-0", "2147483648"] {
    assert_true(
      @migration_lens.ReviewArchive::parse_json(
        original
        .to_json()
        .stringify()
        .replace(
          old="\"format_version\":2",
          new="\"format_version\":" + version,
        ),
      )
      is Err(_),
    )
  }
  for
    extra in [
      "\"unknown\":1,", "\"format_version\":2,", "\"format_versi\\u006fn\":2,",
    ] {
    let text = original.to_json().stringify()
    assert_true(
      @migration_lens.ReviewArchive::parse_json(
        "{" + extra + text[1:].to_owned(),
      )
      is Err(_),
    )
  }
  for bad in ["", " project", "project ", "p\nq", "x".repeat(257)] {
    assert_true(@migration_lens.ReviewArchive::review(bad, [][:]) is Err(_))
  }
  assert_true(
    @migration_lens.ReviewArchive::review("x".repeat(256), [][:]) is Ok(_),
  )
  for key in ["project", "tool_version", "rules_version", "database", "unknown"] {
    let data = original.to_json()
    guard data is { "origin": Object(origin), .. } else { fail("origin") }
    origin[key] = Json(0)
    assert_true(
      @migration_lens.ReviewArchive::parse_json(data.stringify()) is Err(_),
    )
  }
  // v1 decoders and byte-level JSON contracts remain usable independently.
  let report = original.batch.files[0].report
  assert_eq(
    @migration_lens.Report::parse_json(report.to_json().stringify()).unwrap(),
    report,
  )
  assert_eq(
    @migration_lens.BatchReport::parse_json(
      original.batch.to_json().stringify(),
    )
    .unwrap()
    .to_json(),
    original.batch.to_json(),
  )
}

///|
test "v2 deltas preserve duplicate multiplicity additions removals and immutable snapshots" {
  for count in 1..<=24 {
    let before = archive_for("DROP INDEX a;".repeat(count))
    let after = archive_for("-- shifted\n" + "DROP INDEX a;".repeat(count + 1))
    let delta = @migration_lens.compare_archives(before, after).unwrap()
    assert_eq(delta.files[0].retained, count)
    assert_eq(delta.files[0].introduced.length(), 1)
    assert_eq(delta.exit_code(), 1)
    assert_eq(
      @migration_lens.compare_archives(after, after).unwrap().exit_code(),
      0,
    )
    assert_eq(
      @migration_lens.compare_archives(after, before).unwrap().files[0].resolved.length(),
      1,
    )
    let saved = delta.to_json().stringify()
    before.batch.files[0].report.diagnostics.clear()
    assert_eq(delta.to_json().stringify(), saved)
    assert_eq(delta.baseline.origin.project, "orders-service")
  }
}

///|
test "checked archives support file reordering and reject context changes in duplicate occurrences" {
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
  let baseline = @migration_lens.ReviewArchive::review("p", [a, b][:]).unwrap()
  let reordered = @migration_lens.ReviewArchive::review("p", [b, a][:]).unwrap()
  assert_eq(
    @migration_lens.compare_archives(baseline, reordered).unwrap().exit_code(),
    0,
  )
  let removed = @migration_lens.ReviewArchive::review("p", [a][:]).unwrap()
  let delta = @migration_lens.compare_archives(baseline, removed).unwrap()
  assert_eq(delta.files.length(), 2)
  assert_eq(delta.files[1].resolved.length(), 1)
  let duplicate = @migration_lens.ReviewArchive::review("p", [a, a][:]).unwrap()
  let changed = @migration_lens.ReviewArchive::review(
    "p",
    [
      a,
      @migration_lens.Migration::new(
        "a.sql",
        "DROP INDEX a;",
        execution=SimpleQuery,
      ),
    ][:],
  ).unwrap()
  assert_true(@migration_lens.compare_archives(duplicate, changed) is Err(_))
}

///|
test "invalid and incomplete archives retain evidence but cannot pass a baseline" {
  for
    item in [
      archive_for("SELECT 1;"),
      archive_for("DROP INDEX a;", execution=Unknown),
      archive_for("DROP INDEX a;", initial_lock_timeout_ms=-1),
    ] {
    let restored = @migration_lens.ReviewArchive::parse_json(
      item.to_json().stringify(),
    ).unwrap()
    assert_eq(restored.exit_code(), 2)
    assert_true(@migration_lens.compare_archives(restored, restored) is Err(_))
  }
  let item = archive_for("-- 😀\rDROP INDEX a;")
  guard item.to_sarif() is Ok({ "runs": [run], .. }) else { fail("SARIF") }
  assert_true(
    run
    is {
      "tool": { "driver": { "version": "0.1.0", .. }, .. },
      "properties": {
        "migrationLensOrigin": { "project": "orders-service", .. },
        ..
      },
      ..
    },
  )
  assert_eq(item.to_sarif(), item.to_sarif())
}

///|
test "archive rejects invalid Unicode before provenance or SQL can be serialized lossily" {
  for
    broken in [
      "😀".unsafe_substring(start=0, end=1),
      "😀".unsafe_substring(start=1, end=2),
    ] {
    assert_true(@migration_lens.ReviewArchive::review(broken, [][:]) is Err(_))
    for
      input in [
        @migration_lens.Migration::new(broken, "", execution=SeparateStatements),
        @migration_lens.Migration::new(
          "a.sql",
          broken,
          execution=SeparateStatements,
        ),
      ] {
      assert_true(
        @migration_lens.ReviewArchive::review("p", [input][:]) is Err(_),
      )
    }
    assert_true(@migration_lens.ReviewArchive::parse_json(broken) is Err(_))
  }
  let original = archive_for("DROP INDEX a;").to_json().stringify()
  assert_true(
    @migration_lens.ReviewArchive::parse_json(
      original.replace(old="orders-service", new="\\uD800"),
    )
    is Err(_),
  )
  assert_true(
    @migration_lens.ReviewArchive::parse_json(
      "[".repeat(21) + "0" + "]".repeat(21),
    )
    is Err(_),
  )
}
