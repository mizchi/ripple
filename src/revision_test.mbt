///|
test "Revision::zero creates revision with value 0" {
  let r = Revision::zero()
  inspect(r.get(), content="0")
}

///|
test "Revision::new creates revision with specified value" {
  let r = Revision::new(42)
  inspect(r.get(), content="42")
}

///|
test "Revision::next increments the revision" {
  let r1 = Revision::zero()
  let r2 = r1.next()
  let r3 = r2.next()
  inspect(r1.get(), content="0")
  inspect(r2.get(), content="1")
  inspect(r3.get(), content="2")
}

///|
test "Revision::is_after compares revisions correctly" {
  let r1 = Revision::new(1)
  let r2 = Revision::new(2)
  let r3 = Revision::new(2)
  inspect(r2.is_after(r1), content="true")
  inspect(r1.is_after(r2), content="false")
  inspect(r2.is_after(r3), content="false")
}

///|
test "Revision::is_at_or_after compares revisions correctly" {
  let r1 = Revision::new(1)
  let r2 = Revision::new(2)
  let r3 = Revision::new(2)
  inspect(r2.is_at_or_after(r1), content="true")
  inspect(r1.is_at_or_after(r2), content="false")
  inspect(r2.is_at_or_after(r3), content="true")
}

///|
test "Revision::max returns the larger revision" {
  let r1 = Revision::new(1)
  let r2 = Revision::new(5)
  let r3 = Revision::new(3)
  inspect(r1.max(r2).get(), content="5")
  inspect(r2.max(r1).get(), content="5")
  inspect(r2.max(r3).get(), content="5")
}

///|
test "Revision equality" {
  let r1 = Revision::new(5)
  let r2 = Revision::new(5)
  let r3 = Revision::new(6)
  inspect(r1 == r2, content="true")
  inspect(r1 == r3, content="false")
}
