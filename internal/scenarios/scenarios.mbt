///|
priv struct Generator {
  mut state : Int64
}

///|
fn Generator::pick(self : Generator, bound : Int32) -> Int32 {
  // Integer-only Park-Miller recurrence; not cryptographic randomness.
  self.state = self.state * 48271L % 2147483647L
  self.state.to_int() % bound
}

///|
pub struct Scenario {
  seed : Int32
  commands : Array[String]
  index_name : String
}

///|
pub fn Scenario::sentinel(self : Scenario) -> String {
  "CREATE INDEX CONCURRENTLY \{self.index_name} ON migrationlens_diff_probe(id)"
}

///|
pub fn Scenario::sql(self : Scenario) -> String {
  self.commands.join(";\n") + ";\n" + self.sentinel() + ";"
}

///|
/// Generate only valid transaction/savepoint structure. No timeout value/state
/// is simulated: PostgreSQL supplies that oracle. Duplicate names resolve to
/// the latest occurrence, as both ROLLBACK TO and RELEASE require.
pub fn generate(seed : Int32, steps : Int32) -> Result[Scenario, String] {
  if seed < 1 || seed > 2147483646 || steps < 0 || steps > 128 {
    return Err("Require seed 1..2147483646 and steps 0..128")
  }
  let rng : Generator = { state: seed.to_int64(), }
  let commands = ["SET SESSION lock_timeout=100"]
  let marks : Array[String] = []
  let mut active = false
  for _ in 0..<steps {
    match rng.pick(10) {
      0 | 1 | 2 => {
        let value = [0, 1, 50, 100, 101, 1000][rng.pick(6)]
        let scope = if active && rng.pick(2) == 0 { "LOCAL" } else { "SESSION" }
        commands.push("SET \{scope} lock_timeout=\{value}")
      }
      3 => {
        commands.push(
          if active {
            "BEGIN"
          } else {
            "START TRANSACTION ISOLATION LEVEL READ COMMITTED READ WRITE"
          },
        )
        active = true
      }
      4 if active => {
        let name = "point_\{rng.pick(4)}"
        commands.push("SAVEPOINT " + name)
        marks.push(name)
      }
      5 | 6 as choice if active && !marks.is_empty() => {
        let name = marks[rng.pick(marks.length())]
        for i = marks.length() - 1; i >= 0; i = i - 1 {
          if marks[i] == name {
            commands.push(
              (if choice == 5 {
                "ROLLBACK TO SAVEPOINT "
              } else {
                "RELEASE SAVEPOINT "
              }) +
              name,
            )
            marks.truncate(if choice == 5 { i + 1 } else { i })
            break
          }
        }
      }
      7 | 8 as choice if active => {
        commands.push(
          if choice == 7 {
            "END AND CHAIN"
          } else {
            "ABORT AND CHAIN"
          },
        )
        marks.clear()
      }
      9 if active => {
        commands.push(if rng.pick(2) == 0 { "COMMIT" } else { "ROLLBACK" })
        active = false
        marks.clear()
      }
      _ =>
        if !active {
          commands.push("BEGIN")
          active = true
        } else {
          commands.push("SET LOCAL lock_timeout='100ms'")
        }
    }
  }
  Ok({ seed, commands, index_name: "ml_diff_\{seed}", })
}
