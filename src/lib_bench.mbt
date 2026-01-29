///|
/// Benchmark: Input set and get operations
test "bench: Input set/get" (b : @bench.T) {
  let rt = Runtime::new()
  let input : Input[Int, Int] = Input::new(0)
  // Pre-populate
  for i in 0..<1000 {
    input.set(rt, i, i * 2) |> ignore
  }
  b.bench(name="Input::get (1000 items)", fn() {
    for i in 0..<1000 {
      input.get(rt, i) |> ignore
    }
  })
}

///|
/// Benchmark: Query fetch with cache hit
test "bench: Query cache hit" (b : @bench.T) {
  let rt = Runtime::new()
  let input : Input[Int, Int] = Input::new(0)
  input.set(rt, 0, 42) |> ignore
  let query : Query[Int, Int] = Query::new(1, fn(rt, key) {
    input.get(rt, key).unwrap_or(0) * 2
  })
  // Warm up cache
  query.fetch(rt, 0) |> ignore
  b.bench(name="Query::fetch cache hit", fn() {
    for _ in 0..<1000 {
      query.fetch(rt, 0) |> ignore
    }
  })
}

///|
/// Benchmark: Query fetch with cache miss (recompute)
test "bench: Query recompute" (b : @bench.T) {
  let rt = Runtime::new()
  let input : Input[Int, Int] = Input::new(0)
  let query : Query[Int, Int] = Query::new(1, fn(rt, key) {
    input.get(rt, key).unwrap_or(0) * 2
  })
  b.bench(name="Query::fetch recompute", fn() {
    for i in 0..<100 {
      input.set(rt, 0, i) |> ignore
      query.fetch(rt, 0) |> ignore
    }
  })
}

///|
/// Benchmark: Chained queries
test "bench: Chained queries" (b : @bench.T) {
  let rt = Runtime::new()
  let input : Input[Int, Int] = Input::new(0)
  // Query chain: q1 -> q2 -> q3
  let q1 : Query[Int, Int] = Query::new(1, fn(rt, key) {
    input.get(rt, key).unwrap_or(0) + 1
  })
  let q2 : Query[Int, Int] = Query::new(2, fn(rt, key) { q1.fetch(rt, key) * 2 })
  let q3 : Query[Int, Int] = Query::new(3, fn(rt, key) {
    q2.fetch(rt, key) + 10
  })
  input.set(rt, 0, 5) |> ignore
  // Warm up
  q3.fetch(rt, 0) |> ignore
  b.bench(name="Chained queries (3 levels) cache hit", fn() {
    for _ in 0..<1000 {
      q3.fetch(rt, 0) |> ignore
    }
  })
}

///|
/// Benchmark: Many keys
test "bench: Many keys" (b : @bench.T) {
  let rt = Runtime::new()
  let input : Input[Int, Int] = Input::new(0)
  let query : Query[Int, Int] = Query::new(1, fn(rt, key) {
    input.get(rt, key).unwrap_or(0) * 2
  })
  // Pre-populate
  for i in 0..<1000 {
    input.set(rt, i, i) |> ignore
    query.fetch(rt, i) |> ignore
  }
  b.bench(name="Query::fetch 1000 different keys (cached)", fn() {
    for i in 0..<1000 {
      query.fetch(rt, i) |> ignore
    }
  })
}

///|
/// Benchmark: Backdate optimization
test "bench: Backdate" (b : @bench.T) {
  let rt = Runtime::new()
  let input : Input[Int, Int] = Input::new(0)
  // Query returns constant regardless of input
  let query : Query[Int, Int] = Query::new(1, fn(rt, key) {
    input.get(rt, key) |> ignore
    42 // Always returns 42
  })
  input.set(rt, 0, 1) |> ignore
  query.fetch(rt, 0) |> ignore
  b.bench(name="Backdate (same result recompute)", fn() {
    for i in 0..<100 {
      input.set(rt, 0, i) |> ignore
      query.fetch(rt, 0) |> ignore
    }
  })
}

///|
/// Benchmark: Revision operations
test "bench: Revision" (b : @bench.T) {
  b.bench(name="Revision::next 10000 times", fn() {
    let mut r = Revision::zero()
    for _ in 0..<10000 {
      r = r.next()
    }
    b.keep(r)
  })
}

///|
/// Benchmark: Runtime dependency tracking
test "bench: Dependency tracking" (b : @bench.T) {
  let rt = Runtime::new()
  b.bench(name="Record 100 dependencies", fn() {
    rt.push_query(0, 0)
    for i in 0..<100 {
      rt.record_dependency(i, i, Revision::new(i), Durability::Low) |> ignore
    }
    rt.pop_query() |> ignore
  })
}

///|
/// Benchmark: Durability optimization
test "bench: Durability" (b : @bench.T) {
  let rt = Runtime::new()
  // High durability input (rarely changes)
  let stdlib : Input[Int, Int] = Input::new_with_durability(0, Durability::High)
  // Low durability input (frequently changes)
  let user_file : Input[Int, Int] = Input::new_with_durability(
    1,
    Durability::Low,
  )
  // Query depends on high durability input only
  let stdlib_query : Query[Int, Int] = Query::new(2, fn(rt, key) {
    stdlib.get(rt, key).unwrap_or(0) * 2
  })
  // Set high durability input once
  stdlib.set(rt, 0, 100) |> ignore
  stdlib_query.fetch(rt, 0) |> ignore
  b.bench(name="High durability skip (100 low changes)", fn() {
    for i in 0..<100 {
      // Only change low durability input
      user_file.set(rt, 0, i) |> ignore
      // Query should skip recompute (depends only on high durability)
      stdlib_query.fetch(rt, 0) |> ignore
    }
  })
}

///|
/// Benchmark: Deep verify with backdate optimization
/// When intermediate query returns same value, downstream skips recompute
test "bench: Deep verify backdate" (b : @bench.T) {
  let rt = Runtime::new()
  let input : Input[Int, Int] = Input::new(0)
  input.register(rt)
  // Query 1: returns constant (always backdates)
  let q1 : Query[Int, Int] = Query::new(1, fn(rt, key) {
    input.get(rt, key) |> ignore
    42 // Always returns 42
  })
  q1.register(rt)
  // Query 2: depends on q1
  let q2 : Query[Int, Int] = Query::new(2, fn(rt, key) { q1.fetch(rt, key) * 2 })
  // Warm up
  input.set(rt, 0, 1) |> ignore
  q2.fetch(rt, 0) |> ignore
  b.bench(name="Deep verify backdate (100 changes)", fn() {
    for i in 0..<100 {
      input.set(rt, 0, i) |> ignore
      // q1 recomputes, q2 should skip (deep verify + backdate)
      q2.fetch(rt, 0) |> ignore
    }
  })
}

///|
/// Benchmark: Deep verify chain propagation
/// Three-level chain where abs() causes backdate on sign change
test "bench: Deep verify chain" (b : @bench.T) {
  let rt = Runtime::new()
  let input : Input[Int, Int] = Input::new(0)
  input.register(rt)
  // q1: abs - backdates when sign changes
  let q1 : Query[Int, Int] = Query::new(1, fn(rt, key) {
    input.get(rt, key).unwrap_or(0).abs()
  })
  q1.register(rt)
  // q2: depends on q1
  let q2 : Query[Int, Int] = Query::new(2, fn(rt, key) {
    q1.fetch(rt, key) * 10
  })
  q2.register(rt)
  // q3: depends on q2
  let q3 : Query[Int, Int] = Query::new(3, fn(rt, key) { q2.fetch(rt, key) + 1 })
  // Warm up
  input.set(rt, 0, 5) |> ignore
  q3.fetch(rt, 0) |> ignore
  b.bench(name="Deep verify chain (50 positive, 50 negative)", fn() {
    for i in 0..<50 {
      // Alternating between 5 and -5
      input.set(rt, 0, if i % 2 == 0 { 5 } else { -5 }) |> ignore
      q3.fetch(rt, 0) |> ignore
    }
  })
}

///|
/// Benchmark: Intern new values
test "bench: Intern new values" (b : @bench.T) {
  let rt = Runtime::new()
  let strings : Intern[String] = Intern::new(0)
  b.bench(name="Intern 1000 unique strings", fn() {
    for i in 0..<1000 {
      strings.intern(rt, "string_" + i.to_string()) |> ignore
    }
  })
}

///|
/// Benchmark: Intern lookup (existing values)
test "bench: Intern lookup" (b : @bench.T) {
  let rt = Runtime::new()
  let strings : Intern[String] = Intern::new(0)
  // Pre-populate
  for i in 0..<1000 {
    strings.intern(rt, "string_" + i.to_string()) |> ignore
  }
  b.bench(name="Intern lookup 1000 existing", fn() {
    for i in 0..<1000 {
      strings.intern(rt, "string_" + i.to_string()) |> ignore
    }
  })
}

///|
/// Benchmark: Intern ID comparison
test "bench: InternId comparison" (b : @bench.T) {
  let rt = Runtime::new()
  let strings : Intern[String] = Intern::new(0)
  let id1 = strings.intern(rt, "hello")
  let id2 = strings.intern(rt, "world")
  b.bench(name="InternId comparison 10000", fn() {
    for _ in 0..<10000 {
      let _ = id1 == id2
      ()
    }
    b.keep(id1)
  })
}
