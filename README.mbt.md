# incr

Incremental computation library for MoonBit, inspired by Rust's salsa.

## Usage

```moonbit
let db = @incr.Database::new()

// Define inputs
let source_files = db.input[String, String]("source_files")

// Define queries
let parse = db.query[String, Array[String]](
  "parse",
  fn(ctx, path) {
    let content = ctx.get(source_files, path)
    // ... parse logic
  }
)

// Set inputs and run queries
source_files.set(db, "a.mbt", "import b")
let result = parse.get(db, "a.mbt")
```
