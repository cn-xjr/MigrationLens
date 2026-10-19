///|
/// How the caller sends this input. ExistingTransaction is shorthand for
/// separate dispatch in an existing transaction. For simple-query dispatch in
/// an existing transaction, use SimpleQuery with initial_transaction=true.
/// Unknown never establishes a passing review.
pub(all) enum Execution {
  SeparateStatements
  SimpleQuery
  ExistingTransaction
  Unknown
} derive(Debug, Eq, ToJson)

///|
/// Half-open UTF-16 code-unit offsets into the unchanged input string.
pub(all) struct Span {
  start : Int32
  end : Int32
} derive(Debug, Eq, ToJson)

///|
pub(all) enum Severity {
  Error
  Warning
  Incomplete
} derive(Debug, Eq, ToJson)

///|
pub(all) struct Diagnostic {
  code : String
  severity : Severity
  span : Span
  message : String
  help : String
} derive(Debug, Eq, ToJson)

///|
/// Source is retained verbatim. Complete means coverage of this rule set only.
pub(all) struct Report {
  source : String
  /// Lexically delimited statements; an ambiguous malformed suffix is excluded.
  statements : Int32
  complete : Bool
  diagnostics : Array[Diagnostic]
} derive(Debug, Eq)

///|
/// 0: no findings; 1: covered input has findings; 2: analysis incomplete.
pub fn Report::exit_code(self : Report) -> Int32 {
  if !self.complete {
    2
  } else if self.diagnostics.is_empty() {
    0
  } else {
    1
  }
}

///|
pub fn Report::to_json(self : Report) -> Json {
  {
    "format_version": 1,
    "source": self.source,
    "statements": self.statements,
    "complete": self.complete,
    "diagnostics": Json(self.diagnostics),
  }
}

///|
pub fn Report::to_text(self : Report) -> String {
  let out = StringBuilder()
  out.write_string(
    "MigrationLens: \{self.statements} statements; complete=\{self.complete}; exit=\{self.exit_code()}\n",
  )
  for d in self.diagnostics {
    let mut line = 1
    let mut column = 1
    for i in 0..<d.span.start {
      if self.source.code_units()[i] == 10 {
        line += 1
        column = 1
      } else {
        column += 1
      }
    }
    out.write_string(
      "\{d.code} \{line}:\{column}: \{d.message}\n  help: \{d.help}\n",
    )
  }
  out.to_string()
}

///|
fn finding(
  code : String,
  severity : Severity,
  span : Span,
  message : String,
  help : String,
) -> Diagnostic {
  { code, severity, span, message, help, }
}

///|
pub extend Execution with Eq::{equal, not_equal}

///|
pub extend Execution with @debug.Debug::{to_repr}

///|
pub extend Execution with ToJson::{to_json}

///|
pub extend Span with Eq::{equal, not_equal}

///|
pub extend Span with @debug.Debug::{to_repr}

///|
pub extend Span with ToJson::{to_json}

///|
pub extend Severity with Eq::{equal, not_equal}

///|
pub extend Severity with @debug.Debug::{to_repr}

///|
pub extend Severity with ToJson::{to_json}

///|
pub extend Diagnostic with Eq::{equal, not_equal}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with ToJson::{to_json}

///|
pub extend Report with Eq::{equal, not_equal}

///|
pub extend Report with @debug.Debug::{to_repr}
