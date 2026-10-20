///|
fn invalid(message : String) -> Unit {
  println("Cannot restore batch report: \{message}")
  @sys.exit(2)
}

///|
fn main {
  let args = @env.args()[argument_prefix():].to_owned()
  if args.length() != 2 || !["text", "json", "sarif"].contains(args[1]) {
    invalid("usage: migration-lens-report-batch <batch.json> <text|json|sarif>")
    return
  }
  let source = @utf8.decode(@fs.read_file_to_bytes(args[0])) catch {
    e => {
      invalid("Cannot read UTF-8 file: \{Repr(e)}")
      return
    }
  }
  let batch = match @lens.BatchReport::parse_json(source) {
    Ok(b) => b
    Err(e) => {
      invalid(e)
      return
    }
  }
  match args[1] {
    "json" => println(batch.to_json().stringify())
    "sarif" =>
      match batch.to_sarif() {
        Ok(log) => println(log.stringify())
        Err(e) => {
          invalid(e)
          return
        }
      }
    _ => println(batch.to_text())
  }
  @sys.exit(batch.exit_code())
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
