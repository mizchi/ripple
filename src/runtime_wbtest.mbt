///|
test "Runtime::new creates runtime with revision 1" {
  let rt = Runtime::new()
  inspect(rt.current_revision().get(), content="1")
}

///|
test "Runtime::increment_revision increments and returns new revision" {
  let rt = Runtime::new()
  let r2 = rt.increment_revision(Durability::Low)
  inspect(r2.get(), content="2")
  inspect(rt.current_revision().get(), content="2")
  let r3 = rt.increment_revision(Durability::Low)
  inspect(r3.get(), content="3")
}

///|
test "Runtime query stack operations" {
  let rt = Runtime::new()
  inspect(rt.has_active_query(), content="false")
  // Push a query
  rt.push_query(0, 1)
  inspect(rt.has_active_query(), content="true")
  // Record dependencies
  let recorded = rt.record_dependency(1, 2, Revision::new(1), Durability::Low)
  inspect(recorded, content="true")
  // Pop and check edges
  match rt.pop_query() {
    Some((edges, changed_at, durability)) => {
      inspect(edges.length(), content="1")
      inspect(edges[0].ingredient_index, content="1")
      inspect(edges[0].key_index, content="2")
      inspect(changed_at.get(), content="1")
      inspect(durability, content="Low")
    }
    None => panic()
  }
  inspect(rt.has_active_query(), content="false")
}

///|
test "Runtime::record_dependency returns false when no active query" {
  let rt = Runtime::new()
  let recorded = rt.record_dependency(0, 1, Revision::new(1), Durability::Low)
  inspect(recorded, content="false")
}

///|
test "Runtime::is_executing detects cycles" {
  let rt = Runtime::new()
  rt.push_query(0, 1)
  rt.push_query(1, 2)
  inspect(rt.is_executing(0, 1), content="true")
  inspect(rt.is_executing(1, 2), content="true")
  inspect(rt.is_executing(2, 3), content="false")
}

///|
test "ActiveQuery tracks multiple edges" {
  let q = ActiveQuery::new(0, 0)
  q.add_edge(1, 1, Revision::new(1), Durability::High)
  q.add_edge(2, 2, Revision::new(5), Durability::Low)
  q.add_edge(3, 3, Revision::new(3), Durability::Medium)
  let edges = q.get_edges()
  inspect(edges.length(), content="3")
  // changed_at should be max of all dependencies
  inspect(q.get_changed_at().get(), content="5")
  // durability should be min of all dependencies
  inspect(q.get_durability(), content="Low")
}

///|
test "Runtime::last_changed_at tracks durability revisions" {
  let rt = Runtime::new()
  // Initial state - all durability revisions are 0
  inspect(rt.last_changed_at(Durability::Low).get(), content="0")
  inspect(rt.last_changed_at(Durability::High).get(), content="0")
  // Increment with Low durability
  rt.increment_revision(Durability::Low) |> ignore
  inspect(rt.last_changed_at(Durability::Low).get(), content="2")
  inspect(rt.last_changed_at(Durability::High).get(), content="0")
  // Increment with High durability - should also update Low
  rt.increment_revision(Durability::High) |> ignore
  inspect(rt.last_changed_at(Durability::Low).get(), content="3")
  inspect(rt.last_changed_at(Durability::High).get(), content="3")
}
