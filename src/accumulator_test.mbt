///|
test "Accumulator: basic push and get" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // Create accumulator for warnings
  let warnings : @ripple.Accumulator[String] = db.accumulator()
  // Create a query that accumulates warnings
  let check : @ripple.Query[String, Int] = db.query(fn(rt, code) {
    // Simulate checking code and finding warnings
    if code.contains("unused") {
      warnings.push(rt, "Warning: unused variable")
    }
    if code.contains("deprecated") {
      warnings.push(rt, "Warning: deprecated function")
    }
    code.length()
  })
  // Execute query with warnings
  let len = check.fetch(rt, "let unused = 1; deprecated()")
  inspect(len, content="28")
  // Get accumulated warnings
  let w = warnings.get_for_query(check, "let unused = 1; deprecated()")
  inspect(w.length(), content="2")
  inspect(w[0], content="Warning: unused variable")
  inspect(w[1], content="Warning: deprecated function")
}

///|
test "Accumulator: no active query" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let acc : @ripple.Accumulator[Int] = db.accumulator()
  // Push without active query - should be ignored
  acc.push(rt, 42)
  // Should have no values anywhere
  inspect(acc.has_values(0, 0), content="false")
}

///|
test "Accumulator: multiple queries" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let errors : @ripple.Accumulator[String] = db.accumulator()
  // Query A
  let query_a : @ripple.Query[Int, Int] = db.query(fn(rt, x) {
    if x < 0 {
      errors.push(rt, "Error: negative value in A")
    }
    x.abs()
  })
  // Query B
  let query_b : @ripple.Query[Int, Int] = db.query(fn(rt, x) {
    if x > 100 {
      errors.push(rt, "Error: value too large in B")
    }
    x % 100
  })
  // Execute both queries
  query_a.fetch(rt, -5) |> ignore
  query_b.fetch(rt, 150) |> ignore
  // Check errors for each query
  let errors_a = errors.get_for_query(query_a, -5)
  inspect(errors_a.length(), content="1")
  inspect(errors_a[0], content="Error: negative value in A")
  let errors_b = errors.get_for_query(query_b, 150)
  inspect(errors_b.length(), content="1")
  inspect(errors_b[0], content="Error: value too large in B")
}

///|
test "Accumulator: clear values" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let logs : @ripple.Accumulator[String] = db.accumulator()
  let query : @ripple.Query[Int, Int] = db.query(fn(rt, x) {
    logs.push(rt, "processing " + x.to_string())
    x * 2
  })
  query.fetch(rt, 5) |> ignore
  let key = 5
  inspect(logs.count(query.get_index(), key.hash()), content="1")
  // Clear and check
  logs.clear_for_query(query, 5)
  inspect(logs.count(query.get_index(), key.hash()), content="0")
}

///|
test "Accumulator: clear_all" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let metrics : @ripple.Accumulator[Int] = db.accumulator()
  let query : @ripple.Query[Int, Int] = db.query(fn(rt, x) {
    metrics.push(rt, x)
    metrics.push(rt, x * 2)
    x
  })
  query.fetch(rt, 1) |> ignore
  query.fetch(rt, 2) |> ignore
  query.fetch(rt, 3) |> ignore
  // Count all entries
  let mut total = 0
  for entry in metrics.iter() {
    let (_, values) = entry
    total = total + values.length()
  }
  inspect(total, content="6") // 3 queries * 2 values each
  // Clear all
  metrics.clear_all()
  total = 0
  for entry in metrics.iter() {
    let (_, values) = entry
    total = total + values.length()
  }
  inspect(total, content="0")
}

///|
test "Accumulator: has_values and count" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let items : @ripple.Accumulator[String] = db.accumulator()
  let query : @ripple.Query[Int, Int] = db.query(fn(rt, x) {
    for i in 0..<x {
      items.push(rt, "item " + i.to_string())
    }
    x
  })
  let key = 3
  // Before execution
  inspect(items.has_values(query.get_index(), key.hash()), content="false")
  inspect(items.count(query.get_index(), key.hash()), content="0")
  // Execute
  query.fetch(rt, key) |> ignore
  // After execution
  inspect(items.has_values(query.get_index(), key.hash()), content="true")
  inspect(items.count(query.get_index(), key.hash()), content="3")
}

///|
test "Accumulator: chained queries" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let trace : @ripple.Accumulator[String] = db.accumulator()
  // Inner query
  let inner : @ripple.Query[Int, Int] = db.query(fn(rt, x) {
    trace.push(rt, "inner: " + x.to_string())
    x + 1
  })
  // Outer query calls inner
  let outer : @ripple.Query[Int, Int] = db.query(fn(rt, x) {
    trace.push(rt, "outer start: " + x.to_string())
    let result = inner.fetch(rt, x)
    trace.push(rt, "outer end: " + result.to_string())
    result * 2
  })
  // Execute outer
  let result = outer.fetch(rt, 5)
  inspect(result, content="12") // (5 + 1) * 2
  // Check traces - each query has its own accumulated values
  let inner_trace = trace.get_for_query(inner, 5)
  inspect(inner_trace.length(), content="1")
  inspect(inner_trace[0], content="inner: 5")
  let outer_trace = trace.get_for_query(outer, 5)
  inspect(outer_trace.length(), content="2")
  inspect(outer_trace[0], content="outer start: 5")
  inspect(outer_trace[1], content="outer end: 6")
}

///|
/// Realistic example: Compiler diagnostics accumulator
test "Accumulator: compiler diagnostics example" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // Diagnostics accumulator
  let diagnostics : @ripple.Accumulator[(String, String)] = db.accumulator()
  // Simulated type checker
  let type_check : @ripple.Query[String, Bool] = db.query(fn(rt, code) {
    // Check for various issues
    if code.contains("any") {
      diagnostics.push(rt, ("warning", "Avoid using 'any' type"))
    }
    if code.contains("TODO") {
      diagnostics.push(rt, ("info", "TODO comment found"))
    }
    if code.contains("error") {
      diagnostics.push(rt, ("error", "Syntax error detected"))
      return false
    }
    true
  })
  // Check code with issues
  let ok = type_check.fetch(rt, "let x: any = TODO")
  inspect(ok, content="true")
  let diags = diagnostics.get_for_query(type_check, "let x: any = TODO")
  inspect(diags.length(), content="2")
  inspect(diags[0].0, content="warning")
  inspect(diags[1].0, content="info")
}

///|
test "Accumulator: with CycleQuery" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let events : @ripple.Accumulator[String] = db.accumulator()
  let query_ref : Ref[@ripple.CycleQuery[Int, Int]?] = { val: None }
  let query : @ripple.CycleQuery[Int, Int] = db.cycle_query_with_fallback(
    fn(rt, x) {
      events.push(rt, "computing " + x.to_string())
      if x <= 0 {
        0
      } else {
        let self_query = query_ref.val.unwrap()
        self_query.fetch(rt, x - 1) + x
      }
    },
    -1, // fallback for cycles
  )
  query_ref.val = Some(query)
  // This won't create a cycle (different keys)
  let result = query.fetch(rt, 3)
  inspect(result, content="6") // 3 + 2 + 1 + 0
  // Check events
  let e0 = events.get_for_cycle_query(query, 3)
  inspect(e0.length(), content="1")
  let e1 = events.get_for_cycle_query(query, 2)
  inspect(e1.length(), content="1")
  let e2 = events.get_for_cycle_query(query, 1)
  inspect(e2.length(), content="1")
  let e3 = events.get_for_cycle_query(query, 0)
  inspect(e3.length(), content="1")
}
