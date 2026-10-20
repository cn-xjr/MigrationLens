///|
test "typed report JSON round trips preserve every report field and source" {
  for
    sql in [
      "",
      "-- 😀\r\nDROP INDEX idx;",
      "SELECT 1; DROP INDEX CONCURRENTLY a;",
      "SELECT 'unterminated",
      "-- \u0000",
      "x".repeat(1000001),
    ] {
    let report = @migration_lens.review_sql(sql, execution=SeparateStatements)
    let restored = @migration_lens.Report::parse_json(
      report.to_json().stringify(),
    ).unwrap()
    assert_eq(restored, report)
    assert_eq(restored.to_text(), report.to_text())
    assert_eq(restored.to_json().stringify(), report.to_json().stringify())
  }
}

///|
test "report decoder rejects unrepresented fields versions duplicate keys and wrong types" {
  for
    source in [
      "{}", "[]", "{", "{\"format_version\":2,\"source\":\"\",\"statements\":0,\"complete\":true,\"diagnostics\":[]}",
      "{\"format_version\":1,\"source\":\"\",\"statements\":0,\"complete\":true,\"diagnostics\":[],\"unknown\":1}",
      "{\"format_version\":1,\"source\":\"\",\"source\":\"x\",\"statements\":0,\"complete\":true,\"diagnostics\":[]}",
      "{\"format_version\":1,\"source\":\"\",\"sourc\\u0065\":\"x\",\"statements\":0,\"complete\":true,\"diagnostics\":[]}",
      "{\"format_version\":1,\"source\":\"\",\"statements\":-1,\"complete\":true,\"diagnostics\":[]}",
      "{\"format_version\":1,\"source\":\"\",\"statements\":0.5,\"complete\":true,\"diagnostics\":[]}",
      "{\"format_version\":1,\"source\":\"\",\"statements\":2147483648,\"complete\":true,\"diagnostics\":[]}",
      "{\"format_version\":1,\"source\":\"\\uD800\",\"statements\":0,\"complete\":true,\"diagnostics\":[]}",
    ] {
    assert_true(@migration_lens.Report::parse_json(source) is Err(_))
  }
}

///|
test "report decoder validates completion metadata and UTF16 range boundaries" {
  for
    span in [
      "{\"start\":-1,\"end\":0}", "{\"start\":2,\"end\":1}", "{\"start\":0,\"end\":4}",
      "{\"start\":1,\"end\":2}", "{\"start\":0,\"end\":2,\"extra\":0}",
    ] {
    let source = "{\"format_version\":1,\"source\":\"😀\",\"statements\":1,\"complete\":true,\"diagnostics\":[{\"code\":\"TEST\",\"severity\":\"Warning\",\"span\":" +
      span +
      ",\"message\":\"test\",\"help\":\"\"}]}"
    assert_true(@migration_lens.Report::parse_json(source) is Err(_))
  }
  for severity in ["Incomplete", "Unknown"] {
    let source = "{\"format_version\":1,\"source\":\"\",\"statements\":0,\"complete\":true,\"diagnostics\":[{\"code\":\"TEST\",\"severity\":\"" +
      severity +
      "\",\"span\":{\"start\":0,\"end\":0},\"message\":\"test\",\"help\":\"\"}]}"
    assert_true(@migration_lens.Report::parse_json(source) is Err(_))
  }
  let good = @migration_lens.review_sql("", execution=Unknown)
  assert_eq(
    @migration_lens.Report::parse_json(good.to_json().stringify()).unwrap(),
    good,
  )
}

///|
test "saved diagnostics reject extra fields but retain unfamiliar rule IDs and EOF spans" {
  let root = "{\"format_version\":1,\"source\":\"😀\",\"statements\":2147483647,\"complete\":true,\"diagnostics\":["
  let item = "{\"code\":\"CUSTOM_RULE\",\"severity\":\"Warning\",\"span\":{\"start\":2,\"end\":2},\"message\":\"message\",\"help\":\"\"}"
  let good = root + item + "]}"
  let decoded = @migration_lens.Report::parse_json(good).unwrap()
  assert_eq(decoded.statements, 2147483647)
  assert_eq(decoded.diagnostics[0].span.start, 2)
  assert_eq(
    @migration_lens.Report::parse_json(decoded.to_json().stringify()).unwrap(),
    decoded,
  )
  for
    bad in [
      item.replace(old="\"code\":\"CUSTOM_RULE\"", new="\"code\":\"\""),
      item.replace(old="\"message\":\"message\"", new="\"message\":\"\""),
      item.replace(old="\"help\":\"\"", new="\"help\":false"),
      item.replace(old="\"help\":\"\"", new="\"help\":\"\",\"extra\":0"),
      item.replace(old="\"start\":2", new="\"start\":2,\"start\":0"),
      item.replace(old="\"help\":\"\"", new="\"help\":\"\\uDC00\""),
    ] {
    assert_true(@migration_lens.Report::parse_json(root + bad + "]}") is Err(_))
  }
}

///|
test "report integers are checked before lossy floating point rounding" {
  let good = "{\"format_version\":1,\"source\":\"a\",\"statements\":1,\"complete\":true,\"diagnostics\":[]}"
  for
    number in [
      "1.00000000000000001", "2147483647.00000000001", "1e-9999", "-0", "1e0", "1.0",
    ] {
    let source = good.replace(
      old="\"statements\":1",
      new="\"statements\":" + number,
    )
    assert_true(
      @migration_lens.Report::parse_json(source) is Err(_),
      msg=number,
    )
    let version = good.replace(
      old="\"format_version\":1",
      new="\"format_version\":" + number,
    )
    assert_true(
      @migration_lens.Report::parse_json(version) is Err(_),
      msg=number,
    )
  }
  for
    broken in [
      "😀".unsafe_substring(start=0, end=1),
      "😀".unsafe_substring(start=1, end=2),
    ] {
    assert_true(@migration_lens.Report::parse_json(broken) is Err(_))
  }
  assert_true(@migration_lens.Report::parse_json(good) is Ok(_))
}
