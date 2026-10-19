///|
// Validate every token rather than discarding clauses missing from the upstream
// single-name DropIndex AST. Catalog-dependent constraints remain outside scope.
fn index_identifier(word : String) -> Bool {
  if word.has_prefix("\"") && word.has_suffix("\"") {
    return word.length() > 2
  }
  let tokens = @sql.tokenize(dialect=@sql.Postgres::{ }, word) catch {
    _ => return false
  }
  tokens[:] is [@sql.Identifier(_)]
}

///|
fn classify_drop(words : ArrayView[String]) -> Command {
  let mut i = 2
  let concurrent = words.get(i) == Some("CONCURRENTLY")
  if concurrent {
    i += 1
  }
  if words.get(i) == Some("IF") {
    if words.get(i + 1) != Some("EXISTS") {
      return Unsupported
    }
    i += 2
  }
  let mut count = 0
  while i < words.length() {
    if !index_identifier(words[i]) {
      return Unsupported
    }
    i += 1
    if words.get(i) == Some(".") {
      i += 1
      if i >= words.length() || !index_identifier(words[i]) {
        return Unsupported
      }
      i += 1
    }
    count += 1
    if words.get(i) != Some(",") {
      break
    }
    i += 1
    if i == words.length() {
      return Unsupported
    }
  }
  if count == 0 {
    return Unsupported
  }
  let cascade = words.get(i) == Some("CASCADE")
  if cascade || words.get(i) == Some("RESTRICT") {
    i += 1
  }
  if i != words.length() {
    return Unsupported
  }
  if concurrent && (count != 1 || cascade) {
    InvalidIndex(
      "Concurrent index drop requires exactly one name and forbids CASCADE",
    )
  } else {
    Index(concurrent)
  }
}
