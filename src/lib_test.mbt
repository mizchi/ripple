// Integration test: File dependency graph
//
// Use case: Track file dependencies
// file_a imports file_b, file_c
// file_b imports file_d
//
// When file_d changes -> file_b, file_a should be recomputed

///|
/// Helper: parse "import a, b, c" format and extract import names
fn parse_imports(content : String) -> Array[String] {
  let parts : Array[String] = []
  // Check if content starts with "import "
  if not(content.has_prefix("import ")) {
    return parts
  }
  // Extract the part after "import "
  let chars = content.to_array()
  let import_chars = chars[7:]
  let import_part = String::from_array(import_chars)
  // Split by comma and trim spaces
  let mut current = ""
  for c in import_part {
    if c == ',' || c == ' ' {
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

///|
test "parse_imports helper" {
  let imports = parse_imports("import a, b, c")
  inspect(imports.length(), content="3")
  inspect(imports[0], content="a")
  inspect(imports[1], content="b")
  inspect(imports[2], content="c")
}

///|
test "File dependency graph: basic caching" {
  let db = Database::new()
  let rt = db.runtime()
  // Input: file contents
  let files : Input[String, String] = db.input()
  // Query: parse imports from a file
  let mut parse_count = 0
  let parse : Query[String, Array[String]] = db.query(fn(rt, path) {
    parse_count = parse_count + 1
    match files.get(rt, path) {
      Some(content) => parse_imports(content)
      None => []
    }
  })
  // Set up files
  files.set(rt, "a.mbt", "import b, c") |> ignore
  files.set(rt, "b.mbt", "import d") |> ignore
  files.set(rt, "c.mbt", "") |> ignore
  files.set(rt, "d.mbt", "") |> ignore
  // Query file a
  let imports_a = parse.fetch(rt, "a.mbt")
  inspect(imports_a.length(), content="2")
  inspect(parse_count, content="1")
  // Query again - should use cache
  let imports_a2 = parse.fetch(rt, "a.mbt")
  inspect(imports_a2.length(), content="2")
  inspect(parse_count, content="1") // Still 1 - cached
}

///|
test "File dependency graph: recompute on change" {
  let db = Database::new()
  let rt = db.runtime()
  let files : Input[String, String] = db.input()
  let mut parse_count = 0
  let parse : Query[String, Array[String]] = db.query(fn(rt, path) {
    parse_count = parse_count + 1
    match files.get(rt, path) {
      Some(content) => parse_imports(content)
      None => []
    }
  })
  // Set up files
  files.set(rt, "a.mbt", "import b") |> ignore
  // Query
  let imports1 = parse.fetch(rt, "a.mbt")
  inspect(imports1.length(), content="1")
  inspect(parse_count, content="1")
  // Change the file
  files.set(rt, "a.mbt", "import b, c, d") |> ignore
  // Query again - should recompute
  let imports2 = parse.fetch(rt, "a.mbt")
  inspect(imports2.length(), content="3")
  inspect(parse_count, content="2")
}

///|
test "File dependency graph: backdate optimization" {
  let db = Database::new()
  let rt = db.runtime()
  let files : Input[String, String] = db.input()
  let mut parse_count = 0
  let parse : Query[String, Array[String]] = db.query(fn(rt, path) {
    parse_count = parse_count + 1
    match files.get(rt, path) {
      Some(content) => parse_imports(content)
      None => []
    }
  })
  // Set up file
  files.set(rt, "a.mbt", "import b") |> ignore
  // Query
  let _ = parse.fetch(rt, "a.mbt")
  let changed1 = parse.changed_at("a.mbt").unwrap().get()
  inspect(changed1, content="2")
  // Change file to same effective content (still imports b)
  files.set(rt, "a.mbt", "import b ") |> ignore // Added space, but same imports
  // Query again
  let imports2 = parse.fetch(rt, "a.mbt")
  inspect(imports2.length(), content="1")
  inspect(imports2[0], content="b")
  // changed_at should be backdated (same value)
  let changed2 = parse.changed_at("a.mbt").unwrap().get()
  inspect(changed2, content="2") // Backdated to original
}

///|
test "File dependency graph: chained queries" {
  let db = Database::new()
  let rt = db.runtime()
  let files : Input[String, String] = db.input()
  // Query 1: parse imports
  let mut parse_count = 0
  let parse : Query[String, Array[String]] = db.query(fn(rt, path) {
    parse_count = parse_count + 1
    match files.get(rt, path) {
      Some(content) => parse_imports(content)
      None => []
    }
  })
  // Query 2: count imports (depends on parse)
  let mut count_count = 0
  let count_imports : Query[String, Int] = db.query(fn(rt, path) {
    count_count = count_count + 1
    parse.fetch(rt, path).length()
  })
  // Set up file
  files.set(rt, "a.mbt", "import b, c") |> ignore
  // Query count
  let c1 = count_imports.fetch(rt, "a.mbt")
  inspect(c1, content="2")
  inspect(parse_count, content="1")
  inspect(count_count, content="1")
  // Query again - both should be cached
  let c2 = count_imports.fetch(rt, "a.mbt")
  inspect(c2, content="2")
  inspect(parse_count, content="1")
  inspect(count_count, content="1")
  // Change file
  files.set(rt, "a.mbt", "import x, y, z") |> ignore
  // Query again - both should recompute
  let c3 = count_imports.fetch(rt, "a.mbt")
  inspect(c3, content="3")
  inspect(parse_count, content="2")
  inspect(count_count, content="2")
}

///|
test "Multiple inputs and queries" {
  let db = Database::new()
  let rt = db.runtime()
  // Two independent inputs
  let numbers : Input[String, Int] = db.input()
  let multipliers : Input[String, Int] = db.input()
  // Query that uses both
  let compute : Query[String, Int] = db.query(fn(rt, key) {
    let n = numbers.get(rt, key).unwrap_or(0)
    let m = multipliers.get(rt, key).unwrap_or(1)
    n * m
  })
  // Set inputs
  numbers.set(rt, "a", 5) |> ignore
  multipliers.set(rt, "a", 3) |> ignore
  // Query
  let r1 = compute.fetch(rt, "a")
  inspect(r1, content="15")
  // Change only one input
  numbers.set(rt, "a", 10) |> ignore
  let r2 = compute.fetch(rt, "a")
  inspect(r2, content="30")
  // Change the other input
  multipliers.set(rt, "a", 2) |> ignore
  let r3 = compute.fetch(rt, "a")
  inspect(r3, content="20")
}
