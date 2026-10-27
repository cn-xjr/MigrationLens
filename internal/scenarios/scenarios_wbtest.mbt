///|
test "generator is integer deterministic with pinned recurrence" {
  let rng : Generator = { state: 1L, }
  assert_eq(rng.pick(2147483647), 48271)
  assert_eq(rng.pick(2147483647), 182605794)
  for seed in [1, 20261028, 2147483646] {
    let a = generate(seed, 128).unwrap()
    let b = generate(seed, 128).unwrap()
    assert_eq(a.sql(), b.sql())
    assert_eq(a.commands.length(), 129)
    assert_eq(a.index_name, "ml_diff_\{seed}")
  }
}

///|
test "generator rejects invalid bounds and retains minimal input" {
  for (seed, steps) in [(0, 1), (-1, 1), (2147483647, 1), (1, -1), (1, 129)] {
    assert_true(generate(seed, steps) is Err(_))
  }
  assert_eq(generate(1, 0).unwrap().commands, ["SET SESSION lock_timeout=100"])
}

///|
test "generated sequences are wholly covered and structurally legal in both dispatch modes" {
  let seen : Map[String, Bool] = Map([])
  for seed in 1..<=256 {
    let scenario = generate(seed, 64).unwrap()
    for command in scenario.commands {
      for
        prefix in [
          "SAVEPOINT", "RELEASE", "ROLLBACK TO", "END AND CHAIN", "ABORT AND CHAIN",
          "COMMIT", "SET LOCAL", "SET SESSION",
        ] {
        if command.has_prefix(prefix) {
          seen[prefix] = true
        }
      }
    }
    for execution in [@lens.SeparateStatements, SimpleQuery] {
      let report = @lens.review_sql(
        scenario.sql(),
        execution~,
        max_lock_timeout_ms=100,
        initial_lock_timeout_ms=0,
      )
      assert_true(report.complete, msg="seed=\{seed}")
      assert_true(
        !report.diagnostics.any(d => {
          ["ML003", "ML102", "ML106", "ML202", "ML203", "ML204"].contains(
            d.code,
          )
        }),
        msg="seed=\{seed}",
      )
      if execution == SimpleQuery {
        assert_true(report.diagnostics.any(d => d.code == "ML101"))
      }
    }
  }
  for
    prefix in [
      "SAVEPOINT", "RELEASE", "ROLLBACK TO", "END AND CHAIN", "ABORT AND CHAIN",
      "COMMIT", "SET LOCAL", "SET SESSION",
    ] {
    assert_true(seen.contains(prefix), msg=prefix)
  }
}
