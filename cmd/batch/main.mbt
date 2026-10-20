///|
fn input_failure(message : String) -> Unit {
  println("Cannot review migration manifest: \{message}")
  @sys.exit(2)
}

///|
fn main {
  let args = @env.args()[argument_prefix():].to_owned()
  if args.length() < 1 ||
    args.length() > 2 ||
    (args.length() == 2 && args[1] != "--json" && args[1] != "--sarif") {
    input_failure(
      "usage: migration-lens-batch <manifest.json> [--json|--sarif]",
    )
    return
  }
  let source = @utf8.decode(@fs.read_file_to_bytes(args[0])) catch {
    e => {
      input_failure("Cannot read UTF-8 manifest \{args[0]}: \{Repr(e)}")
      return
    }
  }
  let entries = match parse_entries(source) {
    Ok(entries) => entries
    Err(e) => {
      input_failure(e)
      return
    }
  }
  let inputs = []
  for i, entry in entries {
    let source = @utf8.decode(@fs.read_file_to_bytes(entry.path)) catch {
      e => {
        input_failure(
          "Entry \{i} (\{entry.path}): cannot read UTF-8 SQL: \{Repr(e)}",
        )
        return
      }
    }
    inputs.push(
      @lens.Migration::new(
        entry.path,
        source,
        execution=entry.execution,
        initial_transaction=entry.initial_transaction,
        require_lock_timeout=entry.require_lock_timeout,
        max_lock_timeout_ms?=entry.maximum,
      ),
    )
  }
  let batch = @lens.review_migrations(inputs[:])
  if args.get(1) == Some("--sarif") {
    match batch.to_sarif() {
      Ok(data) => println(data.stringify())
      Err(e) => {
        input_failure(e)
        return
      }
    }
  } else if args.get(1) == Some("--json") {
    println(batch.to_json().stringify())
  } else {
    println(batch.to_text())
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
