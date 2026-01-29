# ripple

Incremental computation library for MoonBit, inspired by Rust's salsa.
Changes ripple through the dependency graph, recomputing only what's necessary.

## Usage

```moonbit
let db = @ripple.Database::new()
let rt = db.runtime()

// Define inputs
let source_files : @ripple.Input[String, String] = db.input()
source_files.register(rt)

// Define queries
let parse : @ripple.Query[String, Array[String]] = db.query(
  fn(rt, path) {
    match source_files.get(rt, path) {
      Some(content) => parse_imports(content)
      None => []
    }
  }
)
parse.register(rt)

// Set inputs and run queries
source_files.set(rt, "a.mbt", "import b") |> ignore
let result = parse.fetch(rt, "a.mbt")  // ["b"]

// Change input - only affected queries recompute
source_files.set(rt, "a.mbt", "import b, c") |> ignore
let result2 = parse.fetch(rt, "a.mbt")  // ["b", "c"] - recomputed
```

## Features

- **Automatic dependency tracking**: Dependencies recorded during query execution
- **Minimal recomputation**: Only changed inputs trigger recomputation
- **Deep verification**: Cached results validated against dependency graph
- **Cycle detection**: CycleQuery handles recursive dependencies
- **Value interning**: Deduplicate values with stable IDs
- **Accumulator**: Collect diagnostics/warnings during computation
