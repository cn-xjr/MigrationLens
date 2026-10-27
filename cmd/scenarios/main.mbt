///|
fn summary(sql : String, execution : @lens.Execution) -> Json {
  let report = @lens.review_sql(
    sql,
    execution~,
    max_lock_timeout_ms=100,
    initial_lock_timeout_ms=0,
  )
  let timeout = report.diagnostics
    .filter(d => ["ML201", "ML202", "ML205"].contains(d.code))
    .map(d => Json(d.code))
  {
    "report": report.to_json(),
    "conflict": report.diagnostics.any(d => d.code == "ML101"),
    "timeout_codes": Json(timeout),
  }
}

///|
fn main {
  let args = @env.args()[argument_prefix():].to_owned()
  let values = args.map(arg => @string.parse_int(arg) catch { _ => -1 })
  guard values is [seed, count, steps] &&
    seed >= 1 &&
    seed <= 2147483646 &&
    count >= 1 &&
    count <= 256 &&
    steps >= 0 &&
    steps <= 128 else {
    println(
      "usage: scenarios <seed:1..2147483646> <count:1..256> <steps:0..128>",
    )
    @sys.exit(2)
    return
  }
  let cases : Array[Json] = []
  for i in 0..<count {
    let actual_seed = ((seed.to_int64() - 1L + i.to_int64()) % 2147483646L + 1L).to_int()
    let scenario = @scenario.generate(actual_seed, steps).unwrap()
    cases.push({
      "seed": actual_seed,
      "commands": Json(scenario.commands),
      "sentinel": scenario.sentinel(),
      "index_name": scenario.index_name,
      "sql": scenario.sql(),
      "separate": summary(scenario.sql(), SeparateStatements),
      "simple": summary(scenario.sql(), SimpleQuery),
    })
  }
  let origin = @lens.ReviewArchive::review("migrationlens-differential", [][:]).unwrap().origin
  let plan : Json = {
    "format_version": 1,
    "generator_version": 1,
    "tool_origin": {
      "project": origin.project,
      "tool_version": origin.tool_version,
      "rules_version": origin.rules_version,
      "database": origin.database,
    },
    "seed": seed,
    "count": count,
    "steps": steps,
    "cases": Json(cases),
  }
  println(plan.stringify())
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
