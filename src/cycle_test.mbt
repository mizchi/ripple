///|
test "CycleQuery: basic usage without cycle" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let input : @ripple.Input[Int, Int] = db.input()
  // CycleQuery that doesn't have cycles
  let query : @ripple.CycleQuery[Int, Int] = db.cycle_query(fn(rt, key) {
    input.get(rt, key).unwrap_or(0) * 2
  })
  input.set(rt, 0, 5) |> ignore
  let result = query.fetch(rt, 0)
  inspect(result, content="10")
  // Cache hit
  let result2 = query.fetch(rt, 0)
  inspect(result2, content="10")
}

///|
test "CycleQuery: fallback on direct self-cycle" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // Query that calls itself - direct cycle
  // Use Ref to allow self-reference
  let query_ref : Ref[@ripple.CycleQuery[Int, Int]?] = { val: None }
  let query : @ripple.CycleQuery[Int, Int] = db.cycle_query_with_fallback(
    fn(rt, key) {
      // Try to call self - creates a cycle
      let self_query = query_ref.val.unwrap()
      self_query.fetch(rt, key) + 1
    },
    42, // Fallback value when cycle detected
  )
  query_ref.val = Some(query)
  // First call detects cycle and returns fallback
  let result = query.fetch(rt, 0)
  // The computation tries to call itself, gets fallback 42, then adds 1
  inspect(result, content="43")
}

///|
test "CycleQuery: recover function on cycle" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let query_ref : Ref[@ripple.CycleQuery[Int, Int]?] = { val: None }
  let mut recover_called = false
  let query : @ripple.CycleQuery[Int, Int] = db.cycle_query_with_recover(
    fn(rt, key) {
      let self_query = query_ref.val.unwrap()
      self_query.fetch(rt, key) * 2
    },
    fn(_rt, key) {
      recover_called = true
      key + 100 // Return key + 100 as initial value
    },
  )
  query_ref.val = Some(query)
  let result = query.fetch(rt, 5)
  inspect(recover_called, content="true")
  // Recovery returns 5 + 100 = 105, then computation does 105 * 2 = 210
  inspect(result, content="210")
}

///|
test "CycleQuery: indirect cycle A -> B -> A" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let input : @ripple.Input[Int, Int] = db.input()
  input.set(rt, 0, 10) |> ignore
  // Create two queries that reference each other
  let query_a_ref : Ref[@ripple.CycleQuery[Int, Int]?] = { val: None }
  let query_b_ref : Ref[@ripple.CycleQuery[Int, Int]?] = { val: None }
  // Query A: input + query_b
  let query_a : @ripple.CycleQuery[Int, Int] = db.cycle_query_with_fallback(
    fn(rt, key) {
      let b = query_b_ref.val.unwrap()
      input.get(rt, key).unwrap_or(0) + b.fetch(rt, key)
    },
    0, // Fallback for A
  )
  // Query B: query_a * 2
  let query_b : @ripple.CycleQuery[Int, Int] = db.cycle_query_with_fallback(
    fn(rt, key) {
      let a = query_a_ref.val.unwrap()
      a.fetch(rt, key) * 2
    },
    1, // Fallback for B
  )
  query_a_ref.val = Some(query_a)
  query_b_ref.val = Some(query_b)
  // When we call A:
  // A needs B, B needs A (cycle!)
  // When B calls A, A detects cycle and returns A's fallback (0)
  // B computes: 0 * 2 = 0
  // A computes: 10 + 0 = 10
  let result = query_a.fetch(rt, 0)
  inspect(result, content="10")
}

///|
test "CycleQuery: fixpoint iteration - fibonacci-like" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // A query that converges through iteration
  // f(n) = if cached then cached else initial
  // This simulates a fixpoint computation
  let values : @ripple.Input[Int, Int] = db.input()
  values.set(rt, 0, 1) |> ignore
  let mut compute_count = 0
  let fib_ref : Ref[@ripple.CycleQuery[Int, Int]?] = { val: None }
  let fib : @ripple.CycleQuery[Int, Int] = db.cycle_query_with_fallback(
    fn(rt, key) {
      compute_count = compute_count + 1
      if key <= 1 {
        values.get(rt, key).unwrap_or(1)
      } else {
        let self_query = fib_ref.val.unwrap()
        // This creates cycles that will use fallback
        self_query.fetch(rt, key - 1) + self_query.fetch(rt, key - 2)
      }
    },
    1, // Fallback value
  )
  fib_ref.val = Some(fib)
  // fib(0) = 1 (from input)
  let f0 = fib.fetch(rt, 0)
  inspect(f0, content="1")
  // fib(1) = 1 (from input, but key=1 not set, so unwrap_or(1))
  let f1 = fib.fetch(rt, 1)
  inspect(f1, content="1")
  // fib(2) = fib(1) + fib(0) = 1 + 1 = 2
  let f2 = fib.fetch(rt, 2)
  inspect(f2, content="2")
  // fib(3) = fib(2) + fib(1) = 2 + 1 = 3
  let f3 = fib.fetch(rt, 3)
  inspect(f3, content="3")
}

///|
test "CycleQuery: changed_at and get_durability" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let input : @ripple.Input[Int, Int] = db.input()
  let query : @ripple.CycleQuery[Int, Int] = db.cycle_query(fn(rt, key) {
    input.get(rt, key).unwrap_or(0)
  })
  // Before computation
  inspect(query.changed_at(0), content="None")
  inspect(query.get_durability(0), content="None")
  // After computation
  input.set(rt, 0, 42) |> ignore
  query.fetch(rt, 0) |> ignore
  inspect(not(query.changed_at(0) is None), content="true")
  inspect(query.get_durability(0), content="Some(Low)")
}

///|
test "CycleQuery: maybe_changed_after" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let input : @ripple.Input[Int, Int] = db.input()
  let query : @ripple.CycleQuery[Int, Int] = db.cycle_query(fn(rt, key) {
    input.get(rt, key).unwrap_or(0)
  })
  input.set(rt, 0, 10) |> ignore
  let rev1 = rt.current_revision()
  query.fetch(rt, 0) |> ignore
  // Not changed after rev1 (computed at same revision)
  inspect(query.maybe_changed_after(0, rev1), content="false")
  // Change input
  input.set(rt, 0, 20) |> ignore
  query.fetch(rt, 0) |> ignore
  // Now changed after rev1
  inspect(query.maybe_changed_after(0, rev1), content="true")
}

///|
/// Test showing how cycle detection works with type inference scenario
/// where types depend on each other
test "CycleQuery: type inference simulation" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // Simpler test: a depends on b, b has explicit type
  let explicit_types : @ripple.Input[String, String] = db.input()
  explicit_types.register(rt)
  let infer_ref : Ref[@ripple.CycleQuery[String, String]?] = { val: None }
  let infer_type : @ripple.CycleQuery[String, String] = db.cycle_query_with_fallback(
    fn(rt, name) {
      // Check if there's an explicit type annotation
      match explicit_types.get(rt, name) {
        Some(t) => t
        None => {
          // Infer from related variable
          let self_query = infer_ref.val.unwrap()
          if name == "a" {
            self_query.fetch(rt, "b") // a's type comes from b
          } else {
            "Unknown"
          }
        }
      }
    },
    "Any", // Fallback type when cycle detected
  )
  infer_ref.val = Some(infer_type)
  infer_type.register(rt)
  // First, set "b" to "Int"
  explicit_types.set(rt, "b", "Int") |> ignore
  // "b" is explicitly "Int"
  let type_b = infer_type.fetch(rt, "b")
  inspect(type_b, content="Int")
  // "a" depends on "b", so should get "Int"
  let type_a = infer_type.fetch(rt, "a")
  inspect(type_a, content="Int")
  // Now change "b" to "String"
  explicit_types.set(rt, "b", "String") |> ignore
  // "b" should be "String"
  let type_b2 = infer_type.fetch(rt, "b")
  inspect(type_b2, content="String")
  // "a" should also update to "String"
  let type_a2 = infer_type.fetch(rt, "a")
  inspect(type_a2, content="String")
}

///|
/// Test mutual dependency with cycle (A -> B -> A)
/// Shows how fallback values work in cycle scenarios
test "CycleQuery: mutual dependency cycle" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let base : @ripple.Input[String, Int] = db.input()
  base.register(rt)
  let query_a_ref : Ref[@ripple.CycleQuery[String, Int]?] = { val: None }
  let query_b_ref : Ref[@ripple.CycleQuery[String, Int]?] = { val: None }
  // A = base + B
  let query_a : @ripple.CycleQuery[String, Int] = db.cycle_query_with_fallback(
    fn(rt, key) {
      let b = query_b_ref.val.unwrap()
      base.get(rt, key).unwrap_or(0) + b.fetch(rt, key)
    },
    0,
  )
  // B = A * 2
  let query_b : @ripple.CycleQuery[String, Int] = db.cycle_query_with_fallback(
    fn(rt, key) {
      let a = query_a_ref.val.unwrap()
      a.fetch(rt, key) * 2
    },
    1,
  )
  query_a_ref.val = Some(query_a)
  query_b_ref.val = Some(query_b)
  query_a.register(rt)
  query_b.register(rt)
  // Set base value
  base.set(rt, "x", 10) |> ignore
  // A("x") = 10 + B("x")
  // B("x") = A("x") * 2 → B calls A, A is on stack → A returns fallback 0
  // B("x") = 0 * 2 = 0
  // A("x") = 10 + 0 = 10
  let a1 = query_a.fetch(rt, "x")
  inspect(a1, content="10")
  // B("x") uses cached value 0 (computed during A's execution)
  // This is expected behavior - B was computed with A's fallback
  let b1 = query_b.fetch(rt, "x")
  inspect(b1, content="0")
  // Change base to trigger recomputation
  base.set(rt, "x", 20) |> ignore
  // A recomputes: 20 + B (B will be recomputed too)
  // B calls A, A is on stack → A returns fallback 0
  // B = 0 * 2 = 0
  // A = 20 + 0 = 20
  let a2 = query_a.fetch(rt, "x")
  inspect(a2, content="20")
}
