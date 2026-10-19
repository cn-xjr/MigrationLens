///|
priv struct Fragment {
  span : Span
  text : String
  words : Array[String]
}

///|
priv struct Scan {
  fragments : Array[Fragment]
  errors : Array[Diagnostic]
}

///|
fn word_unit(c : UInt16) -> Bool {
  (c >= 65 && c <= 90) ||
  (c >= 97 && c <= 122) ||
  (c >= 48 && c <= 57) ||
  c == 95 ||
  c >= 128
}

///|
// Comments are blanked only in the parser copy, retaining newlines and offsets.
// Quoted regions remain opaque to statement splitting and keyword recognition.
fn scan(source : String) -> Scan {
  if source.length() > 1000000 || source.code_units().any(c => c == 0) {
    return {
      fragments: [],
      errors: [
        finding(
          "ML004",
          Incomplete,
          { start: 0, end: source.length(), },
          "Input exceeds 1,000,000 UTF-16 units or contains NUL",
          "Split large files at known statement boundaries and reject NUL-containing SQL.",
        ),
      ],
    }
  }
  let fragments = []
  let errors = []
  let units = source.code_units()
  let n = units.length()
  let parser = StringBuilder()
  let words = []
  let mut start = -1
  let mut i = 0
  let mut failed = false
  while i < n && !failed {
    let c = units[i]
    if c == 32 || c == 9 || c == 10 || c == 13 || c == 12 {
      if start >= 0 {
        parser.write_stringview(source[i:i + 1])
      }
      i += 1
    } else if c == 45 && source.get(i + 1) == Some(45) {
      let begin = i
      while i < n && units[i] != 10 {
        i += 1
      }
      if start >= 0 {
        for _ in begin..<i {
          parser.write_string(" ")
        }
      }
    } else if c == 47 && source.get(i + 1) == Some(42) {
      let begin = i
      let mut depth = 1
      i += 2
      while i < n && depth > 0 {
        if units[i] == 47 && source.get(i + 1) == Some(42) {
          depth += 1
          i += 2
        } else if units[i] == 42 && source.get(i + 1) == Some(47) {
          depth -= 1
          i += 2
        } else {
          i += 1
        }
      }
      if depth > 0 {
        errors.push(
          finding(
            "ML001",
            Incomplete,
            { start: begin, end: n, },
            "Unterminated block comment",
            "Close every nested block comment.",
          ),
        )
        failed = true
      }
      if start >= 0 {
        for k in begin..<i {
          parser.write_string(if units[k] == 10 { "\n" } else { " " })
        }
      }
    } else if c == 59 {
      if start >= 0 {
        fragments.push({
          span: { start, end: i + 1, },
          text: parser.to_string(),
          words: words.copy(),
        })
        parser.reset()
        words.clear()
        start = -1
      }
      i += 1
    } else {
      if start < 0 {
        start = i
      }
      let begin = i
      if c == 39 || c == 34 {
        i += 1
        let mut closed = false
        while i < n && !closed {
          if units[i] == c {
            if source.get(i + 1) == Some(c) {
              i += 2
            } else {
              i += 1
              closed = true
            }
          } else if units[i] == 92 && c == 39 {
            // Backslash semantics depend on string prefix/session settings.
            errors.push(
              finding(
                "ML002",
                Incomplete,
                { start: begin, end: n, },
                "Backslash string escapes are outside the lexical contract",
                "Use standard-conforming strings without backslashes for this review.",
              ),
            )
            failed = true
            break
          } else {
            i += 1
          }
        }
        if !closed && !failed {
          errors.push(
            finding(
              "ML001",
              Incomplete,
              { start: begin, end: n, },
              "Unterminated quoted region",
              "Close the string or quoted identifier.",
            ),
          )
          failed = true
        }
      } else if c == 36 {
        i += 1
        while i < n && word_unit(units[i]) {
          i += 1
        }
        if i < n && units[i] == 36 {
          i += 1
          let delimiter = source[begin:i].to_owned()
          let mut closed = false
          while i < n && !closed {
            if units[i] == 36 && source[i:].has_prefix(delimiter) {
              i += delimiter.length()
              closed = true
            } else {
              i += 1
            }
          }
          if !closed {
            errors.push(
              finding(
                "ML001",
                Incomplete,
                { start: begin, end: n, },
                "Unterminated dollar quote",
                "Close the dollar-quoted body with its matching tag.",
              ),
            )
            failed = true
          }
        }
      } else if word_unit(c) {
        i += 1
        while i < n && word_unit(units[i]) {
          i += 1
        }
      } else {
        i += 1
      }
      if !failed {
        let token = source[begin:i].to_owned()
        parser.write_string(token)
        words.push(
          if c == 39 || c == 34 || c == 36 {
            token
          } else {
            token.to_upper()
          },
        )
      }
    }
  }
  if start >= 0 && !failed {
    fragments.push({
      span: { start, end: n, },
      text: parser.to_string(),
      words,
    })
  }
  { fragments, errors, }
}
