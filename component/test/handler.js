// Query handler implementation for testing
// This is provided as the imported 'mizchi:ripple/query-handler' interface.
// The compute function is called by the component when a query needs computation.

let _computeImpl = null;

/** Set the compute implementation. Called by test code after imports are ready. */
export function setComputeImpl(fn) {
  _computeImpl = fn;
}

/** WIT import: compute(query-id: u32, key: string) -> value */
export function compute(queryId, key) {
  if (_computeImpl) return _computeImpl(queryId, key);
  return { tag: 'val-null' };
}
