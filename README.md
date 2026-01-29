# ripple

Incremental computation library for MoonBit, inspired by Rust's [salsa](https://github.com/salsa-rs/salsa).

Changes ripple through the dependency graph, recomputing only what's necessary.

## Features

- **Automatic dependency tracking** - Dependencies recorded during query execution
- **Minimal recomputation** - Only changed inputs trigger recomputation
- **Deep verification** - Cached results validated against dependency graph
- **Cycle detection** - `CycleQuery` handles recursive dependencies with fallback values
- **Value interning** - Deduplicate values with stable IDs
- **Accumulator** - Collect diagnostics/warnings during computation
- **Durability levels** - Skip verification for rarely-changed inputs

## Installation

```bash
moon add mizchi/ripple
```

## Quick Start

```moonbit
let db = @ripple.Database::new()
let rt = db.runtime()

// Define inputs
let files : @ripple.Input[String, String] = db.input()
files.register(rt)

// Define memoized queries
let parse : @ripple.Query[String, Array[String]] = db.query(fn(rt, path) {
  match files.get(rt, path) {
    Some(content) => extract_imports(content)
    None => []
  }
})
parse.register(rt)

// Set inputs and run queries
files.set(rt, "main.mbt", "import lib") |> ignore
let imports = parse.fetch(rt, "main.mbt")  // ["lib"]

// Change input - only affected queries recompute
files.set(rt, "main.mbt", "import lib, utils") |> ignore
let imports2 = parse.fetch(rt, "main.mbt")  // ["lib", "utils"] - recomputed
```

## Core Concepts

| Type | Description |
|------|-------------|
| `Database` | Main facade, creates inputs and queries |
| `Runtime` | Manages revision counter and query stack |
| `Input[K, V]` | External input values (mutable) |
| `Query[K, V]` | Memoized pure function |
| `CycleQuery[K, V]` | Query with cycle detection and recovery |
| `Intern[V]` | Value deduplication with stable IDs |
| `Accumulator[V]` | Collect side-effect data during computation |
| `Revision` | Monotonically increasing change counter |
| `Durability` | Change frequency hint (Low/Medium/High) |

## Documentation

See [src/usage.mbt.md](src/usage.mbt.md) for detailed usage examples with runnable tests.

## Use Cases

- **Incremental compilers** - Re-parse/type-check only changed files
- **Build systems** - Recompile only affected targets
- **IDE features** - Fast re-analysis on code changes
- **Reactive systems** - Efficient derived state updates

## License

MIT
