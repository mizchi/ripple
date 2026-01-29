///|
test "InternId: basic operations" {
  let id1 = @ripple.InternId(1)
  let id2 = @ripple.InternId(1)
  let id3 = @ripple.InternId(2)
  // Equality
  inspect(id1 == id2, content="true")
  inspect(id1 == id3, content="false")
  // Get raw value
  inspect(id1.get(), content="1")
  inspect(id3.get(), content="2")
}

///|
test "Intern: basic intern and lookup" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let strings : @ripple.Intern[String] = @ripple.Intern::new(0)
  // Intern values
  let id1 = strings.intern(rt, "hello")
  let id2 = strings.intern(rt, "world")
  let id3 = strings.intern(rt, "hello") // Same as id1
  // Same value returns same ID
  inspect(id1 == id3, content="true")
  inspect(id1 == id2, content="false")
  // IDs are sequential
  inspect(id1.get(), content="0")
  inspect(id2.get(), content="1")
  // Lookup by ID
  inspect(strings.lookup(rt, id1), content="Some(\"hello\")")
  inspect(strings.lookup(rt, id2), content="Some(\"world\")")
  // Invalid ID returns None
  inspect(strings.lookup(rt, @ripple.InternId(99)), content="None")
}

///|
test "Intern: contains and get_id" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let strings : @ripple.Intern[String] = @ripple.Intern::new(0)
  // Initially empty
  inspect(strings.contains("hello"), content="false")
  inspect(strings.get_id("hello"), content="None")
  // After interning
  let id = strings.intern(rt, "hello")
  inspect(strings.contains("hello"), content="true")
  inspect(strings.get_id("hello"), content="Some(InternId(0))")
  inspect(strings.get_id("hello").unwrap() == id, content="true")
}

///|
test "Intern: len and is_empty" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  let strings : @ripple.Intern[String] = @ripple.Intern::new(0)
  inspect(strings.len(), content="0")
  inspect(strings.is_empty(), content="true")
  strings.intern(rt, "a") |> ignore
  inspect(strings.len(), content="1")
  inspect(strings.is_empty(), content="false")
  strings.intern(rt, "b") |> ignore
  strings.intern(rt, "a") |> ignore // Duplicate
  inspect(strings.len(), content="2") // Still 2
}

///|
test "Intern: durability" {
  let intern_high : @ripple.Intern[String] = @ripple.Intern::new(0)
  inspect(intern_high.get_durability(), content="High") // Default
  let intern_low : @ripple.Intern[String] = @ripple.Intern::new_with_durability(
    1,
    @ripple.Durability::Low,
  )
  inspect(intern_low.get_durability(), content="Low")
}

///|
test "Intern: use with Query" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // Intern for symbols
  let symbols : @ripple.Intern[String] = @ripple.Intern::new(
    db.runtime().current_revision().get(),
  )
  // Query that uses interned symbols
  let mut resolve_count = 0
  let resolve : @ripple.Query[String, @ripple.InternId] = db.query(fn(
    rt,
    name,
  ) {
    resolve_count = resolve_count + 1
    symbols.intern(rt, name)
  })
  // Resolve some symbols
  let id_foo = resolve.fetch(rt, "foo")
  let id_bar = resolve.fetch(rt, "bar")
  let id_foo2 = resolve.fetch(rt, "foo") // Cached
  inspect(id_foo == id_foo2, content="true")
  inspect(id_foo == id_bar, content="false")
  inspect(resolve_count, content="2") // foo and bar, not foo again
}

///|
test "Intern: integer keys" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // Intern can work with any hashable type
  let numbers : @ripple.Intern[Int] = @ripple.Intern::new(0)
  let id1 = numbers.intern(rt, 42)
  let id2 = numbers.intern(rt, 100)
  let id3 = numbers.intern(rt, 42)
  inspect(id1 == id3, content="true")
  inspect(id1 == id2, content="false")
  inspect(numbers.lookup(rt, id1), content="Some(42)")
}

///|
test "Intern: tuple keys (for composite symbols)" {
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // Use tuples for module-qualified names
  let qualified : @ripple.Intern[(String, String)] = @ripple.Intern::new(0)
  let id1 = qualified.intern(rt, ("std", "print"))
  let id2 = qualified.intern(rt, ("std", "println"))
  let id3 = qualified.intern(rt, ("std", "print"))
  inspect(id1 == id3, content="true")
  inspect(id1 == id2, content="false")
  inspect(qualified.lookup(rt, id1), content="Some((\"std\", \"print\"))")
}
