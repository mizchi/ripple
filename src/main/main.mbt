///|
fn main {
  // Example: Simple calculator with memoization
  let db = @incr.Database::new()
  let rt = db.runtime()
  // Input: numbers
  let numbers : @incr.Input[String, Int] = db.input()
  // Query: compute square
  let square : @incr.Query[String, Int] = db.query(fn(rt, key) {
    match numbers.get(rt, key) {
      Some(n) => {
        println("Computing square of " + key + "...")
        n * n
      }
      None => 0
    }
  })
  // Set inputs
  println("Setting x = 5")
  numbers.set(rt, "x", 5) |> ignore
  // First query - computes
  let r1 = square.fetch(rt, "x")
  println("Query square(x): " + r1.to_string())
  // Second query - cached
  let r2 = square.fetch(rt, "x")
  println("Query square(x) again: " + r2.to_string())
  // Change input
  println("\nSetting x = 7")
  numbers.set(rt, "x", 7) |> ignore
  // Query again - recomputes
  let r3 = square.fetch(rt, "x")
  println("Query square(x): " + r3.to_string())
  // Set same value - no revision bump
  println("\nSetting x = 7 again (same value)")
  numbers.set(rt, "x", 7) |> ignore
  // Query - still cached
  let r4 = square.fetch(rt, "x")
  println("Query square(x): " + r4.to_string())
}
