///|
// Every action must be SET NOT NULL; mixed commands can invalidate the CHECK
// proof that PostgreSQL uses to avoid a scan, so their suffix is never dropped.
fn classify_set_not_null(words : ArrayView[String]) -> Command {
  let mut i = 0
  while i < words.length() {
    if words.get(i) != Some("ALTER") {
      return Unsupported
    }
    i += 1
    if words.get(i) == Some("COLUMN") {
      i += 1
    }
    if i >= words.length() || !index_identifier(words[i]) {
      return Unsupported
    }
    i += 1
    if words.get(i) != Some("SET") ||
      words.get(i + 1) != Some("NOT") ||
      words.get(i + 2) != Some("NULL") {
      return Unsupported
    }
    i += 3
    if i == words.length() {
      return SetNotNull
    }
    if words.get(i) != Some(",") {
      return Unsupported
    }
    i += 1
  }
  Unsupported
}

///|
fn not_null_findings(span : Span, diagnostics : Array[Diagnostic]) -> Unit {
  diagnostics.push(
    finding(
      "ML220",
      Warning,
      span,
      "SET NOT NULL requires an ACCESS EXCLUSIVE table lock",
      "Budget blocked reads/writes and lock acquisition; a scan-elision proof does not remove the table lock. Hold the transaction briefly. lock_timeout bounds individual lock waits, not the operation duration.",
    ),
  )
  diagnostics.push(
    finding(
      "ML221",
      Warning,
      span,
      "SET NOT NULL requires null-free data and may scan the table",
      "A valid CHECK proving null absence can avoid the scan if it is not dropped by the same command. Existing invalid not-null constraints are validated. Verify current data, proof eligibility, privileges and ONLY/descendant scope; offline SQL review does not establish catalog facts or scan avoidance.",
    ),
  )
}
