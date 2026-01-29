///|
test "Input::new creates input with given index" {
  let input : Input[String, Int] = Input::new(5)
  inspect(input.get_index(), content="5")
}

///|
test "Input::set stores value and bumps revision" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  // Initial revision is 1
  inspect(rt.current_revision().get(), content="1")
  // Set a value
  let r = input.set(rt, "a", 42)
  inspect(r.get(), content="2")
  inspect(rt.current_revision().get(), content="2")
}

///|
test "Input::set with same value does not bump revision" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  let r1 = input.set(rt, "a", 42)
  inspect(r1.get(), content="2")
  // Set same value again
  let r2 = input.set(rt, "a", 42)
  inspect(r2.get(), content="2") // No change
  inspect(rt.current_revision().get(), content="2")
}

///|
test "Input::set with different value bumps revision" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  let r1 = input.set(rt, "a", 42)
  inspect(r1.get(), content="2")
  // Set different value
  let r2 = input.set(rt, "a", 100)
  inspect(r2.get(), content="3")
}

///|
test "Input::get returns stored value" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  input.set(rt, "a", 42) |> ignore
  match input.get(rt, "a") {
    Some(v) => inspect(v, content="42")
    None => panic()
  }
}

///|
test "Input::get returns None for missing key" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  match input.get(rt, "missing") {
    Some(_) => panic()
    None => ()
  }
}

///|
test "Input::contains checks key existence" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  inspect(input.contains("a"), content="false")
  input.set(rt, "a", 42) |> ignore
  inspect(input.contains("a"), content="true")
}

///|
test "Input::changed_at returns revision" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  input.set(rt, "a", 42) |> ignore
  match input.changed_at("a") {
    Some(r) => inspect(r.get(), content="2")
    None => panic()
  }
}

///|
test "Input::maybe_changed_after detects changes" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  input.set(rt, "a", 42) |> ignore // changed_at = 2
  // Check from revision 1
  inspect(input.maybe_changed_after("a", Revision::new(1)), content="true")
  // Check from revision 2
  inspect(input.maybe_changed_after("a", Revision::new(2)), content="false")
  // Check from revision 3
  inspect(input.maybe_changed_after("a", Revision::new(3)), content="false")
}

///|
test "Input::get records dependency" {
  let rt = Runtime::new()
  let input : Input[String, Int] = Input::new(0)
  input.set(rt, "a", 42) |> ignore
  // Start a query
  rt.push_query(1, 0)
  // Get the value (should record dependency)
  input.get(rt, "a") |> ignore
  // Pop and check edges
  match rt.pop_query() {
    Some((edges, _)) => {
      inspect(edges.length(), content="1")
      inspect(edges[0].ingredient_index, content="0") // Input's index
      inspect(edges[0].changed_at.get(), content="2")
    }
    None => panic()
  }
}
