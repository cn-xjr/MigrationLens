///|
// Reject invalid Unicode explicitly: UTF-8 encoding would otherwise panic.
fn valid_unicode(source : String) -> Bool {
  let units = source.code_units()
  let mut i = 0
  while i < units.length() {
    let c = units[i]
    if c >= 0xD800 && c <= 0xDBFF {
      if i + 1 >= units.length() ||
        units[i + 1] < 0xDC00 ||
        units[i + 1] > 0xDFFF {
        return false
      }
      i += 2
    } else if c >= 0xDC00 && c <= 0xDFFF {
      return false
    } else {
      i += 1
    }
  }
  true
}

///|
fn source_boundary(source : String, offset : Int32) -> Bool {
  offset >= 0 &&
  offset <= source.length() &&
  !(offset > 0 &&
  offset < source.length() &&
  source.code_units()[offset] >= 0xDC00 &&
  source.code_units()[offset] <= 0xDFFF)
}

///|
fn sarif_uri(path : String) -> Result[String, String] {
  let path = path.replace(old="\\", new="/")
  if !valid_unicode(path) ||
    path.is_empty() ||
    path.has_prefix("/") ||
    path.contains(":") ||
    path.code_units().any(c => c < 32 || c == 127) {
    return Err(
      "SARIF requires a repository-relative file path without control characters or a drive/scheme",
    )
  }
  for part in path.split("/") {
    if part.is_empty() || part == "." || part == ".." {
      return Err("SARIF path must not contain empty, dot or parent components")
    }
  }
  let out = StringBuilder()
  let hex = "0123456789ABCDEF"
  for byte in @utf8.encode(path).iter() {
    let c = byte.to_int()
    if (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      c == 45 ||
      c == 46 ||
      c == 95 ||
      c == 126 ||
      c == 47 {
      out.write_char(c.to_char().unwrap())
    } else {
      out.write_string("%")
      out.write_stringview(hex[c / 16:c / 16 + 1])
      out.write_stringview(hex[c % 16:c % 16 + 1])
    }
  }
  Ok(out.to_string())
}

///|
fn sarif_lines(source : String) -> Array[Int32] {
  let starts = [0]
  let mut i = 0
  while i < source.length() {
    let c = source.code_units()[i]
    i += 1
    if c == 13 {
      if source.get(i) == Some(10) {
        i += 1
      }
      starts.push(i)
    } else if c == 10 {
      starts.push(i)
    }
  }
  starts
}

///|
fn sarif_position(starts : Array[Int32], offset : Int32) -> (Int32, Int32) {
  let mut low = 0
  let mut high = starts.length()
  while low + 1 < high {
    let mid = low + (high - low) / 2
    if starts[mid] <= offset {
      low = mid
    } else {
      high = mid
    }
  }
  (low + 1, offset - starts[low] + 1)
}

///|
/// Export every finding and the original source as SARIF 2.1.0. Paths must be
/// repository-relative; Windows separators are normalized and UTF-8 bytes are
/// percent-encoded. Invalid paths, Unicode, diagnostic metadata or spans return
/// Err instead of dropping findings or repairing externally constructed reports.
pub fn Report::to_sarif(
  self : Report,
  artifact_path : String,
) -> Result[Json, String] {
  let uri = match sarif_uri(artifact_path) {
    Ok(uri) => uri
    Err(e) => return Err(e)
  }
  match validate_report(self, "SARIF") {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let lines = sarif_lines(self.source)
  let rules : Array[Json] = []
  let codes : Map[String, Int32] = Map([])
  let results : Array[Json] = []
  for d in self.diagnostics {
    let rule_index = match codes.get(d.code) {
      Some(index) => index
      None => {
        let index = rules.length()
        codes[d.code] = index
        rules.push({ "id": d.code })
        index
      }
    }
    let (start_line, start_column) = sarif_position(lines, d.span.start)
    let (end_line, end_column) = sarif_position(lines, d.span.end)
    results.push({
      "ruleId": d.code,
      "ruleIndex": rule_index,
      "level": if d.severity == Warning {
        "warning"
      } else {
        "error"
      },
      "message": { "text": d.message + "\nHelp: " + d.help },
      "locations": [
        {
          "physicalLocation": {
            "artifactLocation": { "uri": uri, "index": 0 },
            "region": {
              "startLine": start_line,
              "startColumn": start_column,
              "endLine": end_line,
              "endColumn": end_column,
            },
          },
        },
      ],
      "properties": {
        "migrationLensSeverity": Json(d.severity),
        "migrationLensSpan": Json(d.span),
        "migrationLensMessage": d.message,
        "migrationLensHelp": d.help,
      },
    })
  }
  Ok({
    "$schema": "https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json",
    "version": "2.1.0",
    "runs": [
      {
        "tool": {
          "driver": {
            "name": "MigrationLens",
            "informationUri": "https://github.com/cn-xjr/MigrationLens",
            "rules": Json(rules),
          },
        },
        "columnKind": "utf16CodeUnits",
        "newlineSequences": ["\r\n", "\r", "\n"],
        "artifacts": [
          {
            "location": { "uri": uri },
            "contents": { "text": self.source },
            "sourceLanguage": "sql",
          },
        ],
        "invocations": [
          { "executionSuccessful": self.complete, "exitCode": self.exit_code() },
        ],
        "results": Json(results),
        "properties": {
          "migrationLensComplete": self.complete,
          "migrationLensStatements": self.statements,
        },
      },
    ],
  })
}
