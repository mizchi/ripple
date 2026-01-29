///|
test "Durability::to_index" {
  inspect(Durability::Low.to_index(), content="0")
  inspect(Durability::Medium.to_index(), content="1")
  inspect(Durability::High.to_index(), content="2")
}

///|
test "Durability::min" {
  inspect(Durability::Low.min(Durability::High), content="Low")
  inspect(Durability::High.min(Durability::Low), content="Low")
  inspect(Durability::High.min(Durability::High), content="High")
  inspect(Durability::Medium.min(Durability::High), content="Medium")
  inspect(Durability::Low.min(Durability::Medium), content="Low")
}

///|
test "Input with durability" {
  let db = @incr.Database::new()
  // Create high durability input
  let stdlib : @incr.Input[String, Int] = db.input_with_durability(
    @incr.Durability::High,
  )
  inspect(stdlib.get_durability(), content="High")
  // Create low durability input (default)
  let user_file : @incr.Input[String, Int] = db.input()
  inspect(user_file.get_durability(), content="Low")
}

///|
test "Query inherits minimum durability from dependencies" {
  let db = @incr.Database::new()
  let rt = db.runtime()
  let high_input : @incr.Input[Int, Int] = db.input_with_durability(
    @incr.Durability::High,
  )
  let low_input : @incr.Input[Int, Int] = db.input_with_durability(
    @incr.Durability::Low,
  )
  // Query that depends only on high durability
  let high_query : @incr.Query[Int, Int] = db.query(fn(rt, key) {
    high_input.get(rt, key).unwrap_or(0)
  })
  // Query that depends on both
  let mixed_query : @incr.Query[Int, Int] = db.query(fn(rt, key) {
    high_input.get(rt, key).unwrap_or(0) + low_input.get(rt, key).unwrap_or(0)
  })
  high_input.set(rt, 0, 100) |> ignore
  low_input.set(rt, 0, 1) |> ignore
  // Execute queries
  high_query.fetch(rt, 0) |> ignore
  mixed_query.fetch(rt, 0) |> ignore
  // Check durabilities
  inspect(high_query.get_durability(0), content="Some(High)")
  inspect(mixed_query.get_durability(0), content="Some(Low)")
}

///|
test "High durability query skips recompute when low durability changes" {
  let db = @incr.Database::new()
  let rt = db.runtime()
  let stdlib : @incr.Input[Int, Int] = db.input_with_durability(
    @incr.Durability::High,
  )
  let user_file : @incr.Input[Int, Int] = db.input_with_durability(
    @incr.Durability::Low,
  )
  let mut compute_count = 0
  let stdlib_query : @incr.Query[Int, Int] = db.query(fn(rt, key) {
    compute_count = compute_count + 1
    stdlib.get(rt, key).unwrap_or(0) * 2
  })
  // Set stdlib and compute
  stdlib.set(rt, 0, 50) |> ignore
  let r1 = stdlib_query.fetch(rt, 0)
  inspect(r1, content="100")
  inspect(compute_count, content="1")
  // Change user_file (low durability) - should NOT trigger recompute
  user_file.set(rt, 0, 999) |> ignore
  let r2 = stdlib_query.fetch(rt, 0)
  inspect(r2, content="100")
  inspect(compute_count, content="1") // Still 1 - no recompute!
  // Change stdlib (high durability) - should trigger recompute
  stdlib.set(rt, 0, 75) |> ignore
  let r3 = stdlib_query.fetch(rt, 0)
  inspect(r3, content="150")
  inspect(compute_count, content="2") // Now 2
}
