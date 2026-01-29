///|
/// Memo stores a cached query result with its revision metadata.
struct Memo[V] {
  value : V
  /// Revision when this value was last computed
  verified_at : Revision
  /// Revision when this value actually changed
  changed_at : Revision
  /// Dependencies recorded during computation (for future deep verify)
  _edges : Array[QueryEdge]
}

///|
/// Query represents a memoized computation.
/// It caches results and automatically invalidates when dependencies change.
pub struct Query[K, V] {
  /// Unique index for this query
  ingredient_index : Int
  /// The computation function
  compute : (Runtime, K) -> V
  /// Cached results
  memos : @hashmap.HashMap[K, Memo[V]]
}

///|
/// Create a new Query with the given index and computation function.
pub fn[K, V] Query::new(
  ingredient_index : Int,
  compute : (Runtime, K) -> V,
) -> Query[K, V] {
  { ingredient_index, compute, memos: @hashmap.new() }
}

///|
/// Get the ingredient index.
pub fn[K, V] Query::get_index(self : Query[K, V]) -> Int {
  self.ingredient_index
}

///|
/// Fetch the result for a key, using cache if valid or recomputing if necessary.
pub fn[K : Hash + Eq, V : Eq] Query::fetch(
  self : Query[K, V],
  rt : Runtime,
  key : K,
) -> V {
  let key_hash = key.hash()
  // Check for cycle
  if rt.is_executing(self.ingredient_index, key_hash) {
    // For now, panic on cycle. Future: support fixpoint iteration
    panic()
  }
  // Try to use cached value
  match self.memos.get(key) {
    Some(memo) => {
      // Shallow verify: already verified at current revision?
      if memo.verified_at == rt.current_revision() {
        // Record dependency and return cached value
        rt.record_dependency(self.ingredient_index, key_hash, memo.changed_at)
        |> ignore
        return memo.value
      }
      // Need to recompute or deep verify
      // For Phase 1, we just recompute
      let new_value = self.execute(rt, key, key_hash)
      // Backdate optimization: if value unchanged, keep old changed_at
      let memo = self.memos.get(key).unwrap()
      rt.record_dependency(self.ingredient_index, key_hash, memo.changed_at)
      |> ignore
      new_value
    }
    None => {
      // No cached value, compute fresh
      let value = self.execute(rt, key, key_hash)
      let memo = self.memos.get(key).unwrap()
      rt.record_dependency(self.ingredient_index, key_hash, memo.changed_at)
      |> ignore
      value
    }
  }
}

///|
/// Execute the computation and store the result.
fn[K : Hash + Eq, V : Eq] Query::execute(
  self : Query[K, V],
  rt : Runtime,
  key : K,
  key_hash : Int,
) -> V {
  // Push onto query stack
  rt.push_query(self.ingredient_index, key_hash)
  // Execute computation
  let value = (self.compute)(rt, key)
  // Pop and get edges
  let (edges, _deps_changed_at) = rt.pop_query().unwrap()
  // Check if we have an old memo to compare against
  let old_changed_at = match self.memos.get(key) {
    Some(old_memo) =>
      if old_memo.value == value {
        // Value unchanged - backdate
        old_memo.changed_at
      } else {
        // Value changed
        rt.current_revision()
      }
    None =>
      // New value
      rt.current_revision()
  }
  // Store memo
  let memo : Memo[V] = {
    value,
    verified_at: rt.current_revision(),
    changed_at: old_changed_at,
    _edges: edges,
  }
  self.memos.set(key, memo)
  value
}

///|
/// Get the changed_at revision for a key (for dependency tracking).
pub fn[K : Hash + Eq, V] Query::changed_at(
  self : Query[K, V],
  key : K,
) -> Revision? {
  match self.memos.get(key) {
    Some(memo) => Some(memo.changed_at)
    None => None
  }
}

///|
/// Check if the query might have changed after a given revision.
pub fn[K : Hash + Eq, V] Query::maybe_changed_after(
  self : Query[K, V],
  key : K,
  revision : Revision,
) -> Bool {
  match self.memos.get(key) {
    Some(memo) => memo.changed_at.is_after(revision)
    None => true // Not computed yet, considered "changed"
  }
}
