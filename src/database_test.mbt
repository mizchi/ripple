///|
test "Database::new creates database with revision 1" {
  let db = Database::new()
  inspect(db.current_revision().get(), content="1")
}

///|
test "Database::input creates inputs with unique indices" {
  let db = Database::new()
  let input1 : Input[String, Int] = db.input()
  let input2 : Input[String, Int] = db.input()
  inspect(input1.get_index(), content="0")
  inspect(input2.get_index(), content="1")
}

///|
test "Database::query creates queries with unique indices" {
  let db = Database::new()
  let q1 : Query[Int, Int] = db.query(fn(_rt, x) { x * 2 })
  let q2 : Query[Int, Int] = db.query(fn(_rt, x) { x + 1 })
  inspect(q1.get_index(), content="0")
  inspect(q2.get_index(), content="1")
}

///|
test "Database inputs and queries share index space" {
  let db = Database::new()
  let input : Input[String, Int] = db.input()
  let query : Query[Int, Int] = db.query(fn(_rt, x) { x * 2 })
  inspect(input.get_index(), content="0")
  inspect(query.get_index(), content="1")
}

///|
test "Database full workflow" {
  let db = Database::new()
  let rt = db.runtime()
  // Create inputs
  let files : Input[String, String] = db.input()
  // Create a query that depends on input
  let parse : Query[String, Array[String]] = db.query(fn(rt, path) {
    match files.get(rt, path) {
      Some(content) => {
        // Simple "parser": split by comma
        let parts : Array[String] = []
        let mut current = ""
        for c in content {
          if c == ',' {
            if current.length() > 0 {
              parts.push(current)
              current = ""
            }
          } else {
            current = current + c.to_string()
          }
        }
        if current.length() > 0 {
          parts.push(current)
        }
        parts
      }
      None => []
    }
  })
  // Set input
  files.set(rt, "main.mbt", "a,b,c") |> ignore
  // Query
  let imports1 = parse.fetch(rt, "main.mbt")
  inspect(imports1.length(), content="3")
  inspect(imports1[0], content="a")
  inspect(imports1[1], content="b")
  inspect(imports1[2], content="c")
  // Change input
  files.set(rt, "main.mbt", "x,y") |> ignore
  // Query again - should recompute
  let imports2 = parse.fetch(rt, "main.mbt")
  inspect(imports2.length(), content="2")
  inspect(imports2[0], content="x")
  inspect(imports2[1], content="y")
}
