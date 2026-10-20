///|
// Deliberately closed option grammar. Duplicate settings and redundant option/
// keyword combinations remain incomplete rather than guessing server precedence.
fn classify_reindex(words : ArrayView[String]) -> Command {
  let mut i = 1
  let mut concurrent = false
  let mut tablespace = false
  let seen : Array[String] = []
  if words.get(i) == Some("(") {
    i += 1
    while i < words.length() {
      let option = words[i]
      if seen.contains(option) {
        return Unsupported
      }
      seen.push(option)
      i += 1
      match option {
        "CONCURRENTLY" | "VERBOSE" => {
          let enabled = match words.get(i) {
            Some("TRUE" | "ON" | "1") => {
              i += 1
              true
            }
            Some("FALSE" | "OFF" | "0") => {
              i += 1
              false
            }
            Some("," | ")") => true
            _ => return Unsupported
          }
          if option == "CONCURRENTLY" {
            concurrent = enabled
          }
        }
        "TABLESPACE" => {
          if i >= words.length() || !index_identifier(words[i]) {
            return Unsupported
          }
          tablespace = true
          i += 1
        }
        _ => return Unsupported
      }
      match words.get(i) {
        Some(")") => {
          i += 1
          break
        }
        Some(",") => i += 1
        _ => return Unsupported
      }
    }
  }
  if words.get(i) != Some("INDEX") {
    return Unsupported
  }
  i += 1
  if words.get(i) == Some("CONCURRENTLY") {
    if seen.contains("CONCURRENTLY") {
      return Unsupported
    }
    concurrent = true
    i += 1
  }
  match words[i:] {
    [name] if index_identifier(name) => Reindex(concurrent, tablespace)
    [schema, ".", name] if index_identifier(schema) && index_identifier(name) =>
      Reindex(concurrent, tablespace)
    _ => Unsupported
  }
}
