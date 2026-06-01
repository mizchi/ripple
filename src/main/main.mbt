///|
/// Incremental Build System Example
/// Demonstrates incr library with a ninja-like build system
///
/// Features:
/// - File content tracking (Input)
/// - Dependency parsing (Query)
/// - Compilation with caching (Query)
/// - Transitive dependency resolution (Query)
/// - Diagnostics collection (Accumulator)

///|
/// Simulated file content
struct FileContent {
  path : String
  content : String
  mtime : Int // Modification time (simulated)
} derive(Eq, Hash, Debug)

///|
/// Compiled object (simplified)
struct CompiledObject {
  path : String
  code : String // "compiled" output
  deps : Array[String] // Dependencies
} derive(Eq, Debug)

///|
/// Build diagnostic
struct Diagnostic {
  level : String // "error", "warning", "info"
  file : String
  message : String
} derive(Eq, Debug)

///|
/// Parse imports from file content
/// Format: "import foo" or "import foo, bar"
fn parse_imports(content : String) -> Array[String] {
  let imports : Array[String] = []
  let lines = content.split("\n")
  for line in lines {
    let trimmed = line.trim()
    let trimmed_str = trimmed.to_owned()
    if trimmed_str.has_prefix("import ") {
      // Get the part after "import "
      let chars = trimmed_str.to_array()
      let rest_chars = chars[7:]
      let rest = String::from_array(rest_chars)
      let parts = rest.split(",")
      for part in parts {
        let name = part.trim().to_owned()
        if name.length() > 0 {
          imports.push(name)
        }
      }
    }
  }
  imports
}

///|
/// Simple "compilation" - just transforms the content
fn compile_content(path : String, content : String) -> String {
  // Remove imports and add a header
  let lines = content.split("\n")
  let output : Array[String] = []
  output.push("// Compiled: " + path)
  for line in lines {
    let trimmed = line.trim().to_owned()
    if !trimmed.has_prefix("import ") {
      output.push(line.to_owned())
    }
  }
  output.join("\n")
}

///|
fn main {
  println("=== Incremental Build System Demo ===\n")
  // Create database
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // File contents (Input) - simulates reading from filesystem
  let files : @ripple.Input[String, FileContent] = db.input()
  files.register(rt)
  // Diagnostics accumulator
  let diagnostics : @ripple.Accumulator[Diagnostic] = db.accumulator()
  // Parse imports (Query) - takes path without extension
  let parse_imports_query : @ripple.Query[String, Array[String]] = db.query(fn(
    rt,
    name,
  ) {
    let path = name + ".mbt"
    match files.get(rt, path) {
      Some(file) => parse_imports(file.content)
      None => {
        diagnostics.push(rt, {
          level: "error",
          file: path,
          message: "File not found",
        })
        []
      }
    }
  })
  parse_imports_query.register(rt)
  // Compile single file (Query) - takes name without extension
  let mut compile_count = 0
  let compile_file : @ripple.Query[String, CompiledObject?] = db.query(fn(
    rt,
    name,
  ) {
    let path = name + ".mbt"
    compile_count = compile_count + 1
    println("  [compile] " + path)
    match files.get(rt, path) {
      Some(file) => {
        let deps = parse_imports_query.fetch(rt, name)
        // Check for syntax errors
        if file.content.contains("error") {
          diagnostics.push(rt, {
            level: "error",
            file: path,
            message: "Syntax error in file",
          })
          return None
        }
        if file.content.contains("warning") {
          diagnostics.push(rt, {
            level: "warning",
            file: path,
            message: "Deprecated syntax used",
          })
        }
        let code = compile_content(path, file.content)
        Some({ path, code, deps })
      }
      None => None
    }
  })
  compile_file.register(rt)
  // Resolve all dependencies transitively (Query)
  let all_deps_ref : Ref[@ripple.CycleQuery[String, Array[String]]?] = {
    val: None,
  }
  let all_deps : @ripple.CycleQuery[String, Array[String]] = db.cycle_query_with_fallback(
    fn(rt, path) {
      let direct = parse_imports_query.fetch(rt, path)
      let result : Array[String] = []
      for dep in direct {
        result.push(dep)
        // Recursively get transitive deps
        let query = all_deps_ref.val.unwrap()
        let transitive = query.fetch(rt, dep)
        for t in transitive {
          if !result.contains(t) {
            result.push(t)
          }
        }
      }
      result
    },
    [], // Fallback for cycles
  )
  all_deps_ref.val = Some(all_deps)
  all_deps.register(rt)
  // Build a target (compiles all dependencies first)
  let build_target : @ripple.Query[String, Array[CompiledObject]] = db.query(fn(
    rt,
    target,
  ) {
    println("  [build] " + target)
    let deps = all_deps.fetch(rt, target)
    let objects : Array[CompiledObject] = []
    // Compile dependencies first (in reverse order for proper ordering)
    for dep in deps {
      match compile_file.fetch(rt, dep) {
        Some(obj) => objects.push(obj)
        None => ()
      }
    }
    // Compile target itself
    match compile_file.fetch(rt, target) {
      Some(obj) => objects.push(obj)
      None => ()
    }
    objects
  })
  // ========================================
  // Scenario 1: Initial build
  // ========================================
  println("--- Scenario 1: Initial Build ---")
  // Set up source files
  files.set(rt, "main.mbt", {
    path: "main.mbt",
    content: "import lib\nfn main { lib.hello() }",
    mtime: 1,
  })
  |> ignore
  files.set(rt, "lib.mbt", {
    path: "lib.mbt",
    content: "import utils\nfn hello { utils.log(\"hi\") }",
    mtime: 1,
  })
  |> ignore
  files.set(rt, "utils.mbt", {
    path: "utils.mbt",
    content: "fn log(s) { print(s) }",
    mtime: 1,
  })
  |> ignore
  compile_count = 0
  let objects1 = build_target.fetch(rt, "main")
  println("  Built " + objects1.length().to_string() + " objects")
  println("  Compile calls: " + compile_count.to_string())
  println("")
  // ========================================
  // Scenario 2: Rebuild without changes
  // ========================================
  println("--- Scenario 2: Rebuild (no changes) ---")
  compile_count = 0
  let objects2 = build_target.fetch(rt, "main")
  println("  Built " + objects2.length().to_string() + " objects")
  println("  Compile calls: " + compile_count.to_string() + " (cached!)")
  println("")
  // ========================================
  // Scenario 3: Change leaf file (utils.mbt)
  // ========================================
  println("--- Scenario 3: Change utils.mbt ---")
  files.set(rt, "utils.mbt", {
    path: "utils.mbt",
    content: "fn log(s) { print(\"[LOG] \" + s) }",
    mtime: 2,
  })
  |> ignore
  compile_count = 0
  let objects3 = build_target.fetch(rt, "main")
  println("  Built " + objects3.length().to_string() + " objects")
  println(
    "  Compile calls: " + compile_count.to_string() + " (only utils recompiled)",
  )
  println("")
  // ========================================
  // Scenario 4: Change middle file (lib.mbt)
  // ========================================
  println("--- Scenario 4: Change lib.mbt ---")
  files.set(rt, "lib.mbt", {
    path: "lib.mbt",
    content: "import utils\nfn hello { utils.log(\"hello world\") }",
    mtime: 3,
  })
  |> ignore
  compile_count = 0
  let objects4 = build_target.fetch(rt, "main")
  println("  Built " + objects4.length().to_string() + " objects")
  println(
    "  Compile calls: " + compile_count.to_string() + " (only lib recompiled)",
  )
  println("")
  // ========================================
  // Scenario 5: Add new dependency
  // ========================================
  println("--- Scenario 5: Add new dependency ---")
  files.set(rt, "config.mbt", {
    path: "config.mbt",
    content: "let DEBUG = true",
    mtime: 4,
  })
  |> ignore
  files.set(rt, "main.mbt", {
    path: "main.mbt",
    content: "import lib, config\nfn main { if config.DEBUG { lib.hello() } }",
    mtime: 4,
  })
  |> ignore
  compile_count = 0
  let objects5 = build_target.fetch(rt, "main")
  println("  Built " + objects5.length().to_string() + " objects")
  println("  Compile calls: " + compile_count.to_string() + " (main + config)")
  println("")
  // ========================================
  // Scenario 6: File with warning
  // ========================================
  println("--- Scenario 6: File with warning ---")
  files.set(rt, "utils.mbt", {
    path: "utils.mbt",
    content: "// warning: old syntax\nfn log(s) { print(s) }",
    mtime: 5,
  })
  |> ignore
  compile_count = 0
  let objects6 = build_target.fetch(rt, "main")
  println("  Built " + objects6.length().to_string() + " objects")
  // Show diagnostics for utils
  let utils_diags = diagnostics.get_for_query(compile_file, "utils")
  println("  Diagnostics for utils.mbt: " + utils_diags.length().to_string())
  for d in utils_diags {
    println("    [" + d.level + "] " + d.message)
  }
  println("")
  // ========================================
  // Summary
  // ========================================
  println("=== Summary ===")
  println("The incremental build system demonstrates:")
  println("  1. Automatic dependency tracking")
  println("  2. Cache invalidation on file changes")
  println("  3. Minimal recompilation (only affected files)")
  println("  4. Transitive dependency resolution")
  println("  5. Diagnostic accumulation")
  println("\n")
  // Run type checking demo
  run_typelang_demo()
}
