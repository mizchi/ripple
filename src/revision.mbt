///|
/// Revision represents a monotonically increasing counter.
/// Each time an input changes, the revision is incremented.
/// This is the core mechanism for tracking changes in the incremental computation system.
struct Revision {
  value : Int
} derive(Eq, Compare, Show)

///|
/// Create a new Revision with value 0 (initial state).
pub fn Revision::zero() -> Revision {
  { value: 0 }
}

///|
/// Create a new Revision from an integer value.
pub fn Revision::new(value : Int) -> Revision {
  { value, }
}

///|
/// Get the integer value of the revision.
pub fn Revision::get(self : Revision) -> Int {
  self.value
}

///|
/// Create the next revision (increment by 1).
pub fn Revision::next(self : Revision) -> Revision {
  { value: self.value + 1 }
}

///|
/// Check if this revision is after another revision.
pub fn Revision::is_after(self : Revision, other : Revision) -> Bool {
  self.value > other.value
}

///|
/// Check if this revision is at or after another revision.
pub fn Revision::is_at_or_after(self : Revision, other : Revision) -> Bool {
  self.value >= other.value
}

///|
/// Return the maximum of two revisions.
pub fn Revision::max(self : Revision, other : Revision) -> Revision {
  if self.value >= other.value {
    self
  } else {
    other
  }
}
