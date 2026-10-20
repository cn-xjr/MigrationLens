///|
fn invalid(message : String) -> Unit {
  println("Cannot compare reports: \{message}")
  @sys.exit(2)
}

///|
fn read_report(path : String) -> Result[@lens.Report, String] {
  let source = @utf8.decode(@fs.read_file_to_bytes(path)) catch {
    e => return Err("Cannot read UTF-8 report \{path}: \{Repr(e)}")
  }
  @lens.Report::parse_json(source)
}

///|
fn main {
  let args = @env.args()[argument_prefix():].to_owned()
  if args.length() < 2 ||
    args.length() > 3 ||
    (args.length() == 3 && args[2] != "--json") {
    invalid(
      "usage: migration-lens-compare <baseline.json> <current.json> [--json]",
    )
    return
  }
  let baseline = match read_report(args[0]) {
    Ok(r) => r
    Err(e) => {
      invalid("Baseline: " + e)
      return
    }
  }
  let current = match read_report(args[1]) {
    Ok(r) => r
    Err(e) => {
      invalid("Current: " + e)
      return
    }
  }
  let delta = match @lens.compare_reports(baseline, current) {
    Ok(d) => d
    Err(e) => {
      invalid(e)
      return
    }
  }
  if args.length() == 3 {
    println(delta.to_json().stringify())
  } else {
    println(delta.to_text())
  }
  @sys.exit(delta.exit_code())
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
