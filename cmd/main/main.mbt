///|
/// File adapter; analysis lives in the portable library.
fn main {
  let args = @env.args()[argument_prefix():].to_owned()
  if args.length() < 2 || args.length() > 3 {
    println(
      "usage: migration-lens <file.sql> <separate|simple|transaction|unknown> [--json]",
    )
    @sys.exit(2)
    return
  }
  let mode : @lens.Execution = match args[1] {
    "separate" => SeparateStatements
    "simple" => SimpleQuery
    "transaction" => ExistingTransaction
    "unknown" => Unknown
    _ => {
      println("Unknown execution mode: \{args[1]}")
      @sys.exit(2)
      return
    }
  }
  if args.length() == 3 && args[2] != "--json" {
    println("Unknown option: \{args[2]}")
    @sys.exit(2)
    return
  }
  let source = @fs.read_file_to_string(args[0], encoding="utf8") catch {
    e => {
      println("Cannot read UTF-8 SQL file: \{Repr(e)}")
      @sys.exit(2)
      return
    }
  }
  let report = @lens.review_sql(source, execution=mode)
  if args.length() == 3 {
    println(report.to_json().stringify())
  } else {
    println(report.to_text())
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
