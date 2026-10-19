///|
test "quoted delimiters never split a fragment" {
  for
    sql in [
      "SELECT 'a;b';", "SELECT 'a'';b';", "DO $tag$ BEGIN; END; $tag$;", "DO $$$$;",
      "SELECT \"a;\"\"b\";", "SELECT 1 /* ; /* ; */ ; */;",
    ] {
    let result = scan(sql)
    assert_eq(result.fragments.length(), 1)
    assert_true(result.errors.is_empty())
    assert_eq(result.fragments[0].span.end, sql.length())
  }
}

///|
test "all closed fragments survive lexical failure in suffix" {
  let result = scan("DROP INDEX idx; SELECT 'unterminated")
  assert_eq(result.fragments.length(), 1)
  assert_eq(result.errors.length(), 1)
}
