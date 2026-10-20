///|
test "manifest validates versions field names types and policy values" {
  let good = "{\"format_version\":1,\"migrations\":[{\"path\":\"fixtures\\\\reindex.sql\",\"execution\":\"simple\",\"initial_transaction\":true,\"require_lock_timeout\":true,\"max_lock_timeout_ms\":2147483647}]}"
  let entries = parse_entries(good).unwrap()
  assert_eq(entries[0].path, "fixtures/reindex.sql")
  assert_eq(entries[0].execution, @lens.SimpleQuery)
  assert_true(entries[0].initial_transaction && entries[0].require_lock_timeout)
  assert_eq(entries[0].maximum, Some(2147483647))
  for
    source in [
      "{}", "{\"format_version\":2,\"migrations\":[]}", "{\"format_version\":1,\"migrations\":[],\"extra\":true}",
      "{\"format_version\":1,\"migrations\":[]}", "[]", "{",
    ] {
    assert_true(parse_entries(source) is Err(_), msg=source)
  }
  for
    entry in [
      "null", "{}", "{\"path\":\"a.sql\",\"execution\":\"typo\"}", "{\"path\":\"a.sql\",\"execution\":\"separate\",\"extra\":1}",
      "{\"path\":\"a.sql\",\"execution\":\"separate\",\"initial_transaction\":\"true\"}",
      "{\"path\":\"a.sql\",\"execution\":\"separate\",\"require_lock_timeout\":null}",
      "{\"path\":\"a.sql\",\"execution\":\"separate\",\"max_lock_timeout_ms\":1.5}",
      "{\"path\":\"a.sql\",\"execution\":\"separate\",\"max_lock_timeout_ms\":2147483648}",
      "{\"path\":\"a.sql\",\"execution\":\"separate\",\"max_lock_timeout_ms\":0}",
    ] {
    assert_true(
      parse_entries("{\"format_version\":1,\"migrations\":[" + entry + "]}")
      is Err(_),
      msg=entry,
    )
  }
}

///|
test "manifest refuses duplicate decoded keys bad paths and resource overflow" {
  for
    entry in [
      "{\"path\":\"a.sql\",\"path\":\"b.sql\",\"execution\":\"separate\"}", "{\"path\":\"a.sql\",\"p\\u0061th\":\"b.sql\",\"execution\":\"separate\"}",
      "{\"path\":\"../a.sql\",\"execution\":\"separate\"}", "{\"path\":\"C:/a.sql\",\"execution\":\"separate\"}",
      "{\"path\":\"a\\n.sql\",\"execution\":\"separate\"}", "{\"path\":\"a//b.sql\",\"execution\":\"separate\"}",
    ] {
    assert_true(
      parse_entries("{\"format_version\":1,\"migrations\":[" + entry + "]}")
      is Err(_),
    )
  }
  assert_true(
    parse_entries(
      "{\"format_version\":1,\"migrations\":[{\"path\":\"\\uD800.sql\",\"execution\":\"separate\"}]}",
    )
    is Err(_),
  )
  assert_true(
    parse_entries(
      "{\"format_version\":1,\"format_version\":1,\"migrations\":[]}",
    )
    is Err(_),
  )
  assert_true(parse_entries(" ".repeat(1000001)) is Err(_))
  let many = "{\"format_version\":1,\"migrations\":[" +
    "{},".repeat(1000) +
    "{}]}"
  assert_true(parse_entries(many) is Err(_))
  let entry = "{\"path\":\"a.sql\",\"execution\":\"separate\"}"
  let maximum = "{\"format_version\":1,\"migrations\":[" +
    (entry + ",").repeat(999) +
    entry +
    "]}"
  assert_eq(parse_entries(maximum).unwrap().length(), 1000)
  assert_true(
    parse_entries(
      "{\"format_version\":1,\"migrations\":[{\"path\":\"a.sql\",\"execution\":\"unknown\"}]}",
    )
    is Ok(_),
  )
}
