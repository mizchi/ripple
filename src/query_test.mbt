///|
test "Query::new creates query with given index" {
  let q : Query[Int, Int] = Query::new(5, fn(_rt, x) { x * 2 })
  inspect(q.get_index(), content="5")
}

///|
test "Query::fetch computes and caches result" {
  let rt = Runtime::new()
  let mut call_count = 0
  let q : Query[Int, Int] = Query::new(0, fn(_rt, x) {
    call_count = call_count + 1
    x * 2
  })
  // First call - should compute
  let v1 = q.fetch(rt, 10)
  inspect(v1, content="20")
  inspect(call_count, content="1")
  // Second call - should use cache (same revision)
  let v2 = q.fetch(rt, 10)
  inspect(v2, content="20")
  inspect(call_count, content="1") // Still 1
}

///|
test "Query::fetch recomputes after revision change" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  input.set(rt, "x", 5) |> ignore
  let mut call_count = 0
  let q : Query[String, Int] = Query::new(1, fn(rt, key) {
    call_count = call_count + 1
    match input.get(rt, key) {
      Some(v) => v * 2
      None => 0
    }
  })
  // First call
  let v1 = q.fetch(rt, "x")
  inspect(v1, content="10")
  inspect(call_count, content="1")
  // Change input (bumps revision)
  input.set(rt, "x", 7) |> ignore
  // Now fetch should recompute
  let v2 = q.fetch(rt, "x")
  inspect(v2, content="14")
  inspect(call_count, content="2")
}

///|
test "Query::fetch with backdate optimization" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  input.set(rt, "x", 5) |> ignore
  let q : Query[String, Int] = Query::new(1, fn(rt, key) {
    match input.get(rt, key) {
      Some(v) => v % 2 // Returns 0 or 1
      None => 0
    }
  })
  // First call: 5 % 2 = 1
  let v1 = q.fetch(rt, "x")
  inspect(v1, content="1")
  let changed1 = q.changed_at("x")
  inspect(changed1.unwrap().get(), content="2") // Computed at revision 2
  // Change input to 7 (still odd, result same)
  input.set(rt, "x", 7) |> ignore
  let v2 = q.fetch(rt, "x")
  inspect(v2, content="1") // Same result
  let changed2 = q.changed_at("x")
  inspect(changed2.unwrap().get(), content="2") // Backdated to original
}

///|
test "Query records dependencies" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  input.set(rt, "a", 1) |> ignore
  input.set(rt, "b", 2) |> ignore
  let q : Query[String, Int] = Query::new(1, fn(rt, _key) {
    let a = input.get(rt, "a").unwrap_or(0)
    let b = input.get(rt, "b").unwrap_or(0)
    a + b
  })
  // Start tracking at outer level
  rt.push_query(99, 0)
  let result = q.fetch(rt, "sum")
  inspect(result, content="3")
  // Check outer query recorded dependency on q
  match rt.pop_query() {
    Some((edges, _)) => {
      inspect(edges.length(), content="1")
      inspect(edges[0].ingredient_index, content="1") // Query's index
    }
    None => panic()
  }
}

///|
test "Query::maybe_changed_after" {
  let rt = Runtime::new()
  let q : Query[Int, Int] = Query::new(0, fn(_rt, x) { x * 2 })
  // Before computing
  inspect(q.maybe_changed_after(5, Revision::new(1)), content="true")
  // Compute
  q.fetch(rt, 5) |> ignore
  // After computing at revision 1
  inspect(q.maybe_changed_after(5, Revision::zero()), content="true")
  inspect(q.maybe_changed_after(5, Revision::new(1)), content="false")
}
