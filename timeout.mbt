///|
priv enum Timeout {
  Finite(Int32)
  Disabled
  Default
}

///|
priv struct Mark {
  name : String
  session : Timeout
  scoped : Timeout?
}

///|
priv struct TimeoutState {
  mut session : Timeout
  mut scoped : Timeout?
  mut at_begin : Timeout
  marks : Array[Mark]
}

///|
fn TimeoutState::new(initial : Int32?) -> TimeoutState {
  let session = match initial {
    None => Default
    Some(0) => Disabled
    Some(value) => Finite(value)
  }
  // An external transaction's earlier session baseline is not supplied.
  { session, scoped: None, at_begin: Default, marks: [], }
}

///|
fn TimeoutState::begin(self : TimeoutState) -> Unit {
  self.at_begin = self.session
  self.scoped = None
  self.marks.clear()
}

///|
fn TimeoutState::finish(self : TimeoutState, rollback~ : Bool) -> Unit {
  if rollback {
    self.session = self.at_begin
  }
  self.scoped = None
  self.marks.clear()
}

///|
fn TimeoutState::taint(self : TimeoutState) -> Unit {
  self.session = Default
  self.scoped = None
  self.at_begin = Default
  self.marks.clear()
}

///|
fn TimeoutState::mark(self : TimeoutState, name : String) -> Unit {
  self.marks.push({ name, session: self.session, scoped: self.scoped, })
}

///|
fn TimeoutState::restore(
  self : TimeoutState,
  name : String,
  release~ : Bool,
) -> Bool {
  for i = self.marks.length(); i > 0; i = i - 1 {
    let mark = self.marks[i - 1]
    if mark.name == name {
      if release {
        self.marks.truncate(i - 1)
      } else {
        self.session = mark.session
        self.scoped = mark.scoped
        self.marks.truncate(i)
      }
      return true
    }
  }
  false
}

///|
fn TimeoutState::check(
  self : TimeoutState,
  span : Span,
  out : Array[Diagnostic],
  maximum : Int32?,
) -> Unit {
  match self.scoped.unwrap_or(self.session) {
    Finite(milliseconds) =>
      if maximum is Some(limit) && milliseconds > limit {
        out.push(
          finding(
            "ML205",
            Warning,
            span,
            "Effective lock_timeout of \{milliseconds}ms exceeds policy maximum of \{limit}ms",
            "Set a positive timeout at or below the configured maximum in the effective scope.",
          ),
        )
      }
    Disabled =>
      out.push(
        finding(
          "ML201",
          Warning,
          span,
          "lock_timeout is explicitly disabled",
          "Establish a positive finite lock_timeout in the effective scope before this index operation.",
        ),
      )
    Default =>
      out.push(
        finding(
          "ML202",
          Warning,
          span,
          "A finite effective lock_timeout has not been established by this input",
          "Check session defaults or set a positive timeout; unknown does not mean disabled.",
        ),
      )
  }
}

///|
// Restrict to integer milliseconds or quoted integer durations. Values which
// PostgreSQL rounds, evaluates or obtains from configuration are never guessed.
fn parse_timeout(raw : String) -> Timeout? {
  if raw == "DEFAULT" {
    return Some(Default)
  }
  let quoted = raw.has_prefix("'") && raw.has_suffix("'")
  let value = if quoted { raw[1:raw.length() - 1].to_owned() } else { raw }
  let mut end = 0
  while end < value.length() {
    let c = value.code_units()[end]
    if c < 48 || c > 57 {
      break
    }
    end += 1
  }
  if end == 0 {
    return None
  }
  let factor : Int64 = match value[end:].to_owned() {
    "" => 1L
    "ms" if quoted => 1L
    "s" if quoted => 1000L
    "min" if quoted => 60000L
    "h" if quoted => 3600000L
    "d" if quoted => 86400000L
    _ => return None
  }
  let number = @string.parse_int64(value[:end]) catch { _ => return None }
  if number > 2147483647L / factor {
    return None
  }
  Some(if number == 0L { Disabled } else { Finite((number * factor).to_int()) })
}

///|
// PostgreSQL identifier truncation is byte-based. Restrict savepoint names to
// ASCII <=63 bytes, and use the dialect tokenizer to reject reserved keywords.
fn savepoint_name(raw : String) -> String? {
  if raw.has_prefix("\"") && raw.has_suffix("\"") {
    let out = StringBuilder()
    let mut i = 1
    while i < raw.length() - 1 {
      let c = raw.code_units()[i]
      if c == 0 || c > 127 {
        return None
      }
      if c == 34 {
        if raw.get(i + 1) != Some(34) {
          return None
        }
        i += 1
      }
      out.write_stringview(raw[i:i + 1])
      i += 1
    }
    let name = out.to_string()
    return if name.is_empty() || name.length() > 63 { None } else { Some(name) }
  }
  let tokens = @sql.tokenize(dialect=@sql.Postgres::{ }, raw) catch {
    _ => return None
  }
  match tokens[:] {
    [@sql.Identifier(name)] => {
      if name.is_empty() ||
        name.length() > 63 ||
        name.code_units().any(c => c == 0 || c > 127) {
        return None
      }
      Some(name.to_lower())
    }
    _ => None
  }
}
