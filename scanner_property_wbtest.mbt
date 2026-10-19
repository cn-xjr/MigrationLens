///|
test "dollar quote search does not match at an interior surrogate boundary" {
  for sql in ["DO $$😀$$;", "DO $tag$😀$tag$;"] {
    let result = scan(sql)
    assert_eq(result.fragments.length(), 1)
    assert_true(result.errors.is_empty())
    assert_eq(result.fragments[0].span.end, sql.length())
    assert_eq(result.fragments[0].text, sql[:sql.length() - 1].to_owned())
  }
}
