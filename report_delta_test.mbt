///|
test "baseline multiset preserves duplicate counts order and both source reports" {
  let before = @migration_lens.review_sql(
    "DROP INDEX a; DROP INDEX a; DROP INDEX b;",
    execution=SeparateStatements,
  )
  let after = @migration_lens.review_sql(
    "-- 😀\r\nDROP INDEX b; DROP INDEX a; DROP INDEX c; DROP INDEX a; DROP INDEX a;",
    execution=SeparateStatements,
  )
  let delta = @migration_lens.compare_reports(before, after).unwrap()
  assert_eq(delta.retained, 3)
  assert_eq(delta.introduced, [after.diagnostics[2], after.diagnostics[4]])
  assert_true(delta.resolved.is_empty())
  assert_eq(delta.exit_code(), 1)
  assert_eq(delta.baseline, before)
  assert_eq(delta.current, after)
  assert_eq(
    delta.retained + delta.introduced.length(),
    after.diagnostics.length(),
  )
  assert_eq(
    delta.retained + delta.resolved.length(),
    before.diagnostics.length(),
  )
  let reversed = @migration_lens.compare_reports(after, before).unwrap()
  assert_eq(reversed.resolved, delta.introduced)
  assert_eq(reversed.exit_code(), 0)
  assert_true(reversed.introduced.is_empty())
  assert_true(delta.to_text().contains("2 introduced; 0 resolved; 3 retained"))
  assert_eq(
    delta.to_json().stringify(),
    @migration_lens.compare_reports(before, after)
    .unwrap()
    .to_json()
    .stringify(),
  )
  assert_eq(@json.parse(delta.to_json().stringify()), delta.to_json())
}

///|
test "baseline ignores positions but exact SQL and every diagnostic attribute matter" {
  let before = @migration_lens.review_sql(
    "DROP INDEX a;",
    execution=SeparateStatements,
  )
  for sql in ["\nDROP INDEX a;", "-- moved 😀\r\nDROP INDEX a;"] {
    let after = @migration_lens.review_sql(sql, execution=SeparateStatements)
    let delta = @migration_lens.compare_reports(before, after).unwrap()
    assert_eq(delta.retained, 1)
    assert_eq(delta.exit_code(), 0)
    assert_eq(delta.current.exit_code(), 1)
  }
  let formatted = @migration_lens.review_sql(
    "DROP  INDEX a;",
    execution=SeparateStatements,
  )
  let changed = @migration_lens.compare_reports(before, formatted).unwrap()
  assert_eq(changed.introduced.length(), 1)
  assert_eq(changed.resolved.length(), 1)
  let d = before.diagnostics[0]
  for
    changed in [
      @migration_lens.Diagnostic::{
        code: "CHANGED",
        severity: d.severity,
        span: d.span,
        message: d.message,
        help: d.help,
      },
      {
        code: d.code,
        severity: Error,
        span: d.span,
        message: d.message,
        help: d.help,
      },
      {
        code: d.code,
        severity: d.severity,
        span: d.span,
        message: "changed",
        help: d.help,
      },
      {
        code: d.code,
        severity: d.severity,
        span: d.span,
        message: d.message,
        help: "changed",
      },
    ] {
    let after : @migration_lens.Report = {
      source: before.source,
      statements: 1,
      complete: true,
      diagnostics: [changed],
    }
    let delta = @migration_lens.compare_reports(before, after).unwrap()
    assert_eq(delta.retained, 0)
    assert_eq(delta.introduced, [changed])
    assert_eq(delta.resolved, [d])
  }
}

///|
test "baseline cannot hide incomplete or malformed caller constructed reports" {
  let clean = @migration_lens.review_sql("", execution=SeparateStatements)
  let incomplete = @migration_lens.review_sql(
    "SELECT 1;",
    execution=SeparateStatements,
  )
  for
    (before, after) in [
      (clean, incomplete),
      (incomplete, clean),
      (incomplete, incomplete),
    ] {
    assert_true(@migration_lens.compare_reports(before, after) is Err(_))
  }
  for
    span in [
      @migration_lens.Span::{ start: -1, end: 0, },
      { start: 2, end: 1, },
      { start: 1, end: 2, },
      { start: 0, end: 3, },
    ] {
    let bad : @migration_lens.Report = {
      source: "😀",
      statements: 1,
      complete: true,
      diagnostics: [
        { code: "TEST", severity: Warning, span, message: "test", help: "", },
      ],
    }
    assert_true(@migration_lens.compare_reports(clean, bad) is Err(_))
    assert_true(@migration_lens.compare_reports(bad, clean) is Err(_))
  }
  for
    (source, count, severity, message) in [
      ("", -1, @migration_lens.Warning, "test"),
      ("", 0, Incomplete, "test"),
      ("", 0, Warning, ""),
      ("😀".unsafe_substring(start=0, end=1), 0, Warning, "test"),
      ("", 0, Warning, "😀".unsafe_substring(start=1, end=2)),
    ] {
    let bad : @migration_lens.Report = {
      source,
      statements: count,
      complete: true,
      diagnostics: [
        {
          code: "TEST",
          severity,
          span: { start: 0, end: 0, },
          message,
          help: "",
        },
      ],
    }
    assert_true(@migration_lens.compare_reports(clean, bad) is Err(_))
  }
  assert_eq(
    @migration_lens.compare_reports(clean, clean).unwrap().exit_code(),
    0,
  )
}

///|
test "delta snapshots are independent of mutable input diagnostic arrays" {
  let original = @migration_lens.review_sql(
    "DROP INDEX a;",
    execution=SeparateStatements,
  )
  let clean = @migration_lens.review_sql("", execution=SeparateStatements)
  let delta = @migration_lens.compare_reports(clean, original).unwrap()
  let encoded = delta.to_json().stringify()
  original.diagnostics.clear()
  assert_eq(delta.current.diagnostics.length(), 1)
  assert_eq(delta.introduced.length(), 1)
  assert_eq(delta.to_json().stringify(), encoded)
}

///|
test "baseline counts remain conserved across every duplicate distribution" {
  for left in 0..<=6 {
    for right in 0..<=6 {
      let before = @migration_lens.review_sql(
        "DROP INDEX a;".repeat(left),
        execution=SeparateStatements,
      )
      let after = @migration_lens.review_sql(
        "DROP INDEX a;".repeat(right),
        execution=SeparateStatements,
      )
      let delta = @migration_lens.compare_reports(before, after).unwrap()
      assert_eq(delta.retained, if left < right { left } else { right })
      assert_eq(delta.retained + delta.introduced.length(), right)
      assert_eq(delta.retained + delta.resolved.length(), left)
      assert_eq(delta.exit_code(), if right > left { 1 } else { 0 })
    }
  }
}
