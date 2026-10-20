///|
// Closed BEGIN/START TRANSACTION mode grammar. Repeated categories are rejected
// conservatively instead of guessing precedence; commas may be omitted in PG.
fn classify_begin(words : ArrayView[String]) -> Command {
  let seen : Map[String, Unit] = Map([])
  let mut i = 0
  let mut read_only = false
  let mut deferrable = false
  while i < words.length() {
    let category = words[i]
    if seen.contains(category) {
      return Unsupported
    }
    match words[i:] {
      ["ISOLATION", "LEVEL", "SERIALIZABLE", ..] => i += 3
      ["ISOLATION", "LEVEL", "REPEATABLE", "READ", ..]
      | ["ISOLATION", "LEVEL", "READ", "COMMITTED" | "UNCOMMITTED", ..] =>
        i += 4
      ["READ", "ONLY" | "WRITE", ..] => {
        read_only = words[i + 1] == "ONLY"
        i += 2
      }
      ["DEFERRABLE", ..] => {
        deferrable = true
        i += 1
      }
      ["NOT", "DEFERRABLE", ..] => i += 2
      _ => return Unsupported
    }
    let category = if category == "NOT" { "DEFERRABLE" } else { category }
    if seen.contains(category) {
      return Unsupported
    }
    seen[category] = ()
    if words.get(i) == Some(",") {
      i += 1
      if i == words.length() {
        return Unsupported
      }
    }
  }
  Begin(read_only~, deferrable~)
}
