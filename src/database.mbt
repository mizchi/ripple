///|
/// Database is the main facade for the incremental computation system.
/// It manages the runtime, inputs, and queries.
pub struct Database {
  /// The runtime state
  runtime : Runtime
  /// Counter for assigning ingredient indices
  mut next_index : Int
}

///|
/// Create a new Database.
pub fn Database::new() -> Database {
  { runtime: Runtime::new(), next_index: 0 }
}

///|
/// Get the current revision.
pub fn Database::current_revision(self : Database) -> Revision {
  self.runtime.current_revision()
}

///|
/// Create a new Input registered with this database.
pub fn[K, V] Database::input(self : Database) -> Input[K, V] {
  let index = self.next_index
  self.next_index = self.next_index + 1
  Input::new(index)
}

///|
/// Create a new Query registered with this database.
pub fn[K, V] Database::query(
  self : Database,
  compute : (Runtime, K) -> V,
) -> Query[K, V] {
  let index = self.next_index
  self.next_index = self.next_index + 1
  Query::new(index, compute)
}

///|
/// Get the runtime (for use with inputs and queries).
pub fn Database::runtime(self : Database) -> Runtime {
  self.runtime
}
