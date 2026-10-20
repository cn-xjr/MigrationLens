///|
fn sarif_field(value : Json, key : String) -> Json {
  guard value is Object(fields) else { abort("expected JSON object") }
  fields.get(key).unwrap()
}

///|
fn sarif_array(value : Json) -> Array[Json] {
  guard value is Array(items) else { abort("expected JSON array") }
  items
}

///|
fn sarif_first(value : Json) -> Json {
  sarif_array(value)[0]
}

///|
fn sarif_run(value : Json) -> Json {
  sarif_first(sarif_field(value, "runs"))
}

///|
test "SARIF retains every finding original source severity and completion" {
  let sql = "SELECT 1; DROP INDEX a; DROP INDEX b;"
  let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
  let data = report.to_sarif("migrations/one.sql").unwrap()
  let run = sarif_run(data)
  assert_eq(sarif_field(data, "version"), Json("2.1.0"))
  let results = sarif_array(sarif_field(run, "results"))
  assert_eq(results.length(), report.diagnostics.length())
  for i, result in results {
    assert_eq(sarif_field(result, "ruleId"), Json(report.diagnostics[i].code))
    let props = sarif_field(result, "properties")
    assert_eq(
      sarif_field(props, "migrationLensSpan"),
      Json(report.diagnostics[i].span),
    )
    assert_eq(
      sarif_field(props, "migrationLensSeverity"),
      Json(report.diagnostics[i].severity),
    )
    assert_eq(
      sarif_field(props, "migrationLensHelp"),
      Json(report.diagnostics[i].help),
    )
    assert_eq(
      sarif_field(props, "migrationLensMessage"),
      Json(report.diagnostics[i].message),
    )
  }
  let artifact = sarif_first(sarif_field(run, "artifacts"))
  assert_eq(sarif_field(sarif_field(artifact, "contents"), "text"), Json(sql))
  let invocation = sarif_first(sarif_field(run, "invocations"))
  assert_eq(sarif_field(invocation, "executionSuccessful"), Json(false))
  assert_eq(sarif_field(invocation, "exitCode"), Json(2))
  let driver = sarif_field(sarif_field(run, "tool"), "driver")
  assert_eq(sarif_array(sarif_field(driver, "rules")).length(), 2)
  assert_eq(sarif_field(results[0], "level"), Json("error"))
  assert_eq(sarif_field(results[1], "level"), Json("warning"))
  assert_eq(@json.parse(data.stringify()), data)
  assert_eq(
    data.stringify(),
    report.to_sarif("migrations/one.sql").unwrap().stringify(),
  )
}

///|
test "SARIF paths encode reserved characters and normalize Windows separators" {
  let report = @migration_lens.review_sql("", execution=SeparateStatements)
  let data = report.to_sarif("migrations\\中文 😀#%.sql").unwrap()
  let run = sarif_run(data)
  let artifact = sarif_first(sarif_field(run, "artifacts"))
  assert_eq(
    sarif_field(sarif_field(artifact, "location"), "uri"),
    Json("migrations/%E4%B8%AD%E6%96%87%20%F0%9F%98%80%23%25.sql"),
  )
  for
    path in [
      "", "/a.sql", "C:\\a.sql", "../a.sql", "a/../b.sql", "./a.sql", "a//b.sql",
      "a/", "a\n.sql",
    ] {
    assert_true(report.to_sarif(path) is Err(_), msg=path)
  }
  assert_true(report.to_sarif("good.sql") is Ok(_))
}

///|
test "SARIF locations use UTF16 columns and all standard newline sequences" {
  let report : @migration_lens.Report = {
    source: "😀\r\na\rb\nc",
    statements: 1,
    complete: true,
    diagnostics: [
      {
        code: "TEST",
        severity: Warning,
        span: { start: 0, end: 2, },
        message: "emoji",
        help: "help",
      },
      {
        code: "TEST",
        severity: Warning,
        span: { start: 8, end: 9, },
        message: "last line",
        help: "help",
      },
    ],
  }
  let results = sarif_array(
    sarif_field(sarif_run(report.to_sarif("one.sql").unwrap()), "results"),
  )
  let first = sarif_field(
    sarif_field(
      sarif_first(sarif_field(results[0], "locations")),
      "physicalLocation",
    ),
    "region",
  )
  assert_eq(first, {
    "startLine": 1,
    "startColumn": 1,
    "endLine": 1,
    "endColumn": 3,
  })
  let last = sarif_field(
    sarif_field(
      sarif_first(sarif_field(results[1], "locations")),
      "physicalLocation",
    ),
    "region",
  )
  assert_eq(last, {
    "startLine": 4,
    "startColumn": 1,
    "endLine": 4,
    "endColumn": 2,
  })
}

///|
test "SARIF rejects invalid public spans and inconsistent completion" {
  for (start, end) in [(-1, 0), (2, 1), (0, 4), (1, 2)] {
    let report : @migration_lens.Report = {
      source: "😀",
      statements: 1,
      complete: true,
      diagnostics: [
        {
          code: "TEST",
          severity: Warning,
          span: { start, end, },
          message: "test",
          help: "help",
        },
      ],
    }
    assert_true(report.to_sarif("one.sql") is Err(_))
  }
  let invalid : @migration_lens.Report = {
    source: "",
    statements: 0,
    complete: true,
    diagnostics: [
      {
        code: "TEST",
        severity: Incomplete,
        span: { start: 0, end: 0, },
        message: "test",
        help: "help",
      },
    ],
  }
  assert_true(invalid.to_sarif("one.sql") is Err(_))
  let empty = @migration_lens.review_sql("", execution=Unknown)
    .to_sarif("one.sql")
    .unwrap()
  let invocation = sarif_first(sarif_field(sarif_run(empty), "invocations"))
  assert_eq(sarif_field(invocation, "executionSuccessful"), Json(false))
  let good = @migration_lens.review_sql(
      "DROP INDEX CONCURRENTLY a;",
      execution=SeparateStatements,
    )
    .to_sarif("one.sql")
    .unwrap()
  assert_eq(sarif_array(sarif_field(sarif_run(good), "results")).length(), 0)
}

///|
test "SARIF rejects invalid metadata and accepts zero-width EOF locations" {
  for (code, message) in [("", "test"), ("TEST", "")] {
    let report : @migration_lens.Report = {
      source: "",
      statements: 0,
      complete: true,
      diagnostics: [
        {
          code,
          severity: Warning,
          span: { start: 0, end: 0, },
          message,
          help: "",
        },
      ],
    }
    assert_true(report.to_sarif("one.sql") is Err(_))
  }
  let negative : @migration_lens.Report = {
    source: "",
    statements: -1,
    complete: false,
    diagnostics: [],
  }
  assert_true(negative.to_sarif("one.sql") is Err(_))
  let eof : @migration_lens.Report = {
    source: "a\n",
    statements: 1,
    complete: true,
    diagnostics: [
      {
        code: "TEST",
        severity: Warning,
        span: { start: 2, end: 2, },
        message: "EOF",
        help: "",
      },
    ],
  }
  let first = sarif_first(
    sarif_field(sarif_run(eof.to_sarif("one.sql").unwrap()), "results"),
  )
  let region = sarif_field(
    sarif_field(
      sarif_first(sarif_field(first, "locations")),
      "physicalLocation",
    ),
    "region",
  )
  assert_eq(region, {
    "startLine": 2,
    "startColumn": 1,
    "endLine": 2,
    "endColumn": 1,
  })
}

///|
test "SARIF refuses unpaired surrogates before URI or JSON encoding" {
  for
    broken in [
      "😀".unsafe_substring(start=0, end=1),
      "😀".unsafe_substring(start=1, end=2),
    ] {
    let report : @migration_lens.Report = {
      source: broken,
      statements: 0,
      complete: false,
      diagnostics: [],
    }
    assert_true(report.to_sarif("one.sql") is Err(_))
    let clean = @migration_lens.review_sql("", execution=SeparateStatements)
    assert_true(clean.to_sarif(broken) is Err(_))
    let metadata : @migration_lens.Report = {
      source: "",
      statements: 0,
      complete: true,
      diagnostics: [
        {
          code: "TEST",
          severity: Warning,
          span: { start: 0, end: 0, },
          message: broken,
          help: "",
        },
      ],
    }
    assert_true(metadata.to_sarif("one.sql") is Err(_))
  }
}
