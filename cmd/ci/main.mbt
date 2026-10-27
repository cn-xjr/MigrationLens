///|
suberror ReviewFailure {
  ReviewFailure(String)
}

///|
fn read_utf8(path : String) -> String raise {
  @utf8.decode(@fs.read_file_to_bytes(path)) catch {
    e => raise ReviewFailure("Cannot read UTF-8 input \{path}: \{Repr(e)}")
  }
}

///|
fn save(output : String, name : String, text : String) -> Unit raise {
  @fs.write_string_to_file(output + "/" + name, text) catch {
    e => raise ReviewFailure("Cannot write \{name}: \{Repr(e)}")
  }
}

///|
fn review(
  project : String,
  manifest_path : String,
  output : String,
  baseline : String?,
) -> (Int32, Int32) raise {
  let manifest = match @manifest.parse_entries(read_utf8(manifest_path)) {
    Ok(manifest) => manifest
    Err(e) => raise ReviewFailure("Manifest: " + e)
  }
  let inputs = []
  for entry in manifest.entries {
    inputs.push(
      @lens.Migration::new(
        entry.path,
        read_utf8(entry.path),
        execution=entry.execution,
        initial_transaction=entry.initial_transaction,
        require_lock_timeout=entry.require_lock_timeout,
        max_lock_timeout_ms?=entry.maximum,
      ),
    )
  }
  let archive = match
    @lens.ReviewArchive::review(
      project,
      inputs[:],
      initial_lock_timeout_ms?=manifest.initial_lock_timeout_ms,
    ) {
    Ok(archive) => archive
    Err(e) => raise ReviewFailure("Review configuration: " + e)
  }
  // Save absolute evidence before any baseline failure or finding can gate CI.
  save(output, "archive.json", archive.to_json().stringify())
  save(output, "report.txt", archive.to_text())
  let sarif = match archive.to_sarif() {
    Ok(sarif) => sarif
    Err(e) => raise ReviewFailure("SARIF export: " + e)
  }
  save(output, "report.sarif.json", sarif.stringify())
  let absolute = archive.exit_code()
  let gate = if baseline is Some(path) {
    let previous = match @lens.ReviewArchive::parse_json(read_utf8(path)) {
      Ok(previous) => previous
      Err(e) => raise ReviewFailure("Baseline: " + e)
    }
    let delta = match @lens.compare_archives(previous, archive) {
      Ok(delta) => delta
      Err(e) => raise ReviewFailure("Baseline comparison: " + e)
    }
    save(output, "delta.json", delta.to_json().stringify())
    save(output, "delta.txt", delta.to_text())
    delta.exit_code()
  } else {
    absolute
  }
  (absolute, gate)
}

///|
fn write_status(
  output : String,
  code : Int32,
  absolute : Int32?,
  baseline_used : Bool,
  message : String,
) -> Unit raise {
  let data : Json = {
    "format_version": 1,
    "exit_code": code,
    "absolute_exit_code": match absolute {
      Some(value) => Json(value)
      None => Json::null()
    },
    "baseline_used": baseline_used,
    "message": message,
  }
  save(output, "status.json", data.stringify())
}

///|
fn main {
  let args = @env.args()[argument_prefix():].to_owned()
  if args.length() < 3 || args.length() > 4 {
    println(
      "usage: migration-lens-ci <project> <manifest.json> <fresh-output-directory> [trusted-v2-baseline.json]",
    )
    @sys.exit(2)
    return
  }
  let output = args[2]
  if @fs.path_exists(output) {
    println("Output already exists; choose a fresh directory: " + output)
    @sys.exit(2)
    return
  }
  // A fresh directory prevents stale successful reports from being uploaded
  // after a failed run. Existing directories and files are never overwritten.
  @fs.create_dir(output) catch {
    e => {
      println("Cannot create fresh output directory \{output}: \{Repr(e)}")
      @sys.exit(2)
      return
    }
  }
  let baseline = args.get(3)
  let code = try {
    write_status(output, 2, None, baseline is Some(_), "Review did not finish")
    let (absolute, gate) = review(args[0], args[1], output, baseline)
    write_status(
      output,
      gate,
      Some(absolute),
      baseline is Some(_),
      "Review finished; inspect full archive for absolute findings",
    )
    println(
      "MigrationLens CI: absolute=\{absolute}; gate=\{gate}; reports=\{output}",
    )
    gate
  } catch {
    e => {
      let message = "Review failed: \{Repr(e)}"
      println(message)
      write_status(output, 2, None, baseline is Some(_), message) catch {
        io => println("Cannot save failure status: \{Repr(io)}")
      }
      2
    }
  }
  @sys.exit(code)
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
