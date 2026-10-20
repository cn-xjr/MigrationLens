///|
// One closed relation name and one supported action. Bulk moves and extra
// clauses are not reduced to a single-index operation.
fn classify_alter_index(words : ArrayView[String]) -> Command {
  let mut i = 2
  if words.get(i) == Some("IF") {
    if words.get(i + 1) != Some("EXISTS") {
      return Unsupported
    }
    i += 2
  }
  if i >= words.length() || !index_identifier(words[i]) {
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
  match words[i:] {
    ["RENAME", "TO", name] if index_identifier(name) => RenameIndex
    ["SET", "TABLESPACE", name] if index_identifier(name) => MoveIndex
    _ => Unsupported
  }
}
