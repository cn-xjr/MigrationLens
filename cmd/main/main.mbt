///|
/// File adapter; analysis lives in the portable library.
fn main {
  let args = @env.args()[argument_prefix():].to_owned()
  if args.length() < 2 || args.length() > 6 {
    println(
      "usage: migration-lens <file.sql> <separate|simple|transaction|unknown> [--json] [--require-lock-timeout] [--initial-transaction] [--max-lock-timeout-ms=N]",
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
  let mut json_output = false
  let mut require_lock_timeout = false
  let mut initial_transaction = false
  let mut max_lock_timeout_ms : Int32? = None
  for option in args[2:] {
    if option.strip_prefix("--max-lock-timeout-ms=") is Some(value) {
      let parsed = @string.parse_int(value) catch { _ => 0 }
      if parsed <= 0 || max_lock_timeout_ms is Some(_) {
        println(
          "Invalid or repeated --max-lock-timeout-ms: use one integer from 1 through 2147483647",
        )
        @sys.exit(2)
        return
      }
      max_lock_timeout_ms = Some(parsed)
      continue
    }
    match option {
      "--json" => json_output = true
      "--require-lock-timeout" => require_lock_timeout = true
      "--initial-transaction" => initial_transaction = true
      _ => {
        println("Unknown option: \{option}")
        @sys.exit(2)
        return
      }
    }
  }
  let source = @utf8.decode(@fs.read_file_to_bytes(args[0])) catch {
    e => {
      println("Cannot read UTF-8 SQL file: \{Repr(e)}")
      @sys.exit(2)
      return
    }
  }
  let report = @lens.review_sql(
    source,
    execution=mode,
    initial_transaction~,
    require_lock_timeout~,
    max_lock_timeout_ms?,
  )
  if json_output {
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
