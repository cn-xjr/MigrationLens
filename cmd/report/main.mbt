///|
fn invalid_report(message : String) -> Unit {
  println("Cannot load saved report: \{message}")
  @sys.exit(2)
}

///|
fn main {
  let args = @env.args()[argument_prefix():].to_owned()
  if args.length() < 2 ||
    args.length() > 3 ||
    (args[1] != "text" && args[1] != "json" && args[1] != "sarif") ||
    (args[1] == "sarif" && args.length() != 3) ||
    (args[1] != "sarif" && args.length() != 2) {
    invalid_report(
      "usage: migration-lens-report <report.json> <text|json|sarif> [repository-relative-artifact-path]",
    )
    return
  }
  let source = @utf8.decode(@fs.read_file_to_bytes(args[0])) catch {
    e => {
      invalid_report("Cannot read UTF-8 file: \{Repr(e)}")
      return
    }
  }
  let report = match @lens.Report::parse_json(source) {
    Ok(report) => report
    Err(e) => {
      invalid_report(e)
      return
    }
  }
  match args[1] {
    "json" => println(report.to_json().stringify())
    "sarif" =>
      match report.to_sarif(args[2]) {
        Ok(log) => println(log.stringify())
        Err(e) => {
          invalid_report(e)
          return
        }
      }
    _ => println(report.to_text())
  }
  @sys.exit(report.exit_code())
}

///|
#cfg(target="js")
fn argument_prefix() -> Int32 {
  2
}

///|
#cfg(target="wasm")
fn argument_prefix() -> Int32 {
  1
}

///|
#cfg(target="wasm-gc")
fn argument_prefix() -> Int32 {
  1
}

///|
#cfg(target="native")
fn argument_prefix() -> Int32 {
  1
}
