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
  if !content.has_prefix("import ") {
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

///|
/// Deep Verify Test: Downstream query should not recompute when
/// intermediate query output doesn't change (backdate propagation)
test "Deep verify with backdate: downstream query skips recompute" {
  let db = Database::new()
  let rt = db.runtime()
  // Input that can change
  let input : Input[Int, Int] = db.input()
  input.register(rt) // Register verifier for deep verify
  // Query 1: returns constant regardless of input (will backdate)
  let mut q1_count = 0
  let q1 : Query[Int, Int] = db.query(fn(rt, key) {
    q1_count = q1_count + 1
    input.get(rt, key) |> ignore // Read input (creates dependency)
    42 // Always returns 42
  })
  q1.register(rt) // Register q1 for deep verify
  // Query 2: depends on q1
  let mut q2_count = 0
  let q2 : Query[Int, Int] = db.query(fn(rt, key) {
    q2_count = q2_count + 1
    q1.fetch(rt, key) * 2
  })
  // Initial setup
  input.set(rt, 0, 100) |> ignore
  let r1 = q2.fetch(rt, 0)
  inspect(r1, content="84")
  inspect(q1_count, content="1")
  inspect(q2_count, content="1")
  // Change input - q1 will recompute but return same value (backdate)
  input.set(rt, 0, 200) |> ignore
  let r2 = q2.fetch(rt, 0)
  inspect(r2, content="84") // Same result
  inspect(q1_count, content="2") // q1 recomputed
  inspect(q2_count, content="1") // q2 did NOT recompute (deep verify + backdate)
}

///|
/// Deep Verify Test: Downstream recomputes when intermediate output changes
test "Deep verify: downstream recomputes when intermediate changes" {
  let db = Database::new()
  let rt = db.runtime()
  let input : Input[Int, Int] = db.input()
  input.register(rt)
  // Query 1: returns input * 2
  let mut q1_count = 0
  let q1 : Query[Int, Int] = db.query(fn(rt, key) {
    q1_count = q1_count + 1
    input.get(rt, key).unwrap_or(0) * 2
  })
  q1.register(rt)
  // Query 2: depends on q1
  let mut q2_count = 0
  let q2 : Query[Int, Int] = db.query(fn(rt, key) {
    q2_count = q2_count + 1
    q1.fetch(rt, key) + 10
  })
  // Initial setup
  input.set(rt, 0, 5) |> ignore
  let r1 = q2.fetch(rt, 0)
  inspect(r1, content="20") // 5 * 2 + 10
  inspect(q1_count, content="1")
  inspect(q2_count, content="1")
  // Change input - both should recompute
  input.set(rt, 0, 15) |> ignore
  let r2 = q2.fetch(rt, 0)
  inspect(r2, content="40") // 15 * 2 + 10
  inspect(q1_count, content="2")
  inspect(q2_count, content="2") // Also recomputed
}

///|
/// Deep Verify Test: Three-level query chain
test "Deep verify: three-level chain" {
  let db = Database::new()
  let rt = db.runtime()
  let input : Input[Int, Int] = db.input()
  input.register(rt)
  let mut q1_count = 0
  let q1 : Query[Int, Int] = db.query(fn(rt, key) {
    q1_count = q1_count + 1
    input.get(rt, key).unwrap_or(0).abs() // abs causes backdate for negative change
  })
  q1.register(rt)
  let mut q2_count = 0
  let q2 : Query[Int, Int] = db.query(fn(rt, key) {
    q2_count = q2_count + 1
    q1.fetch(rt, key) * 10
  })
  q2.register(rt)
  let mut q3_count = 0
  let q3 : Query[Int, Int] = db.query(fn(rt, key) {
    q3_count = q3_count + 1
    q2.fetch(rt, key) + 1
  })
  // Initial: input = 5
  input.set(rt, 0, 5) |> ignore
  let r1 = q3.fetch(rt, 0)
  inspect(r1, content="51") // |5| * 10 + 1
  inspect(q1_count, content="1")
  inspect(q2_count, content="1")
  inspect(q3_count, content="1")
  // Change to -5: abs(5) == abs(-5), so q1 backdates
  input.set(rt, 0, -5) |> ignore
  let r2 = q3.fetch(rt, 0)
  inspect(r2, content="51") // |(-5)| * 10 + 1 = same
  inspect(q1_count, content="2") // q1 recomputed
  inspect(q2_count, content="1") // q2 skipped (q1 backdated)
  inspect(q3_count, content="1") // q3 skipped (q2 not changed)
  // Change to 10: output changes
  input.set(rt, 0, 10) |> ignore
  let r3 = q3.fetch(rt, 0)
  inspect(r3, content="101") // |10| * 10 + 1
  inspect(q1_count, content="3")
  inspect(q2_count, content="2")
  inspect(q3_count, content="2")
}
