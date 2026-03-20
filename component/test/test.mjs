// ripple-component E2E test
import { setComputeImpl } from './handler.js';
import { ripple } from './gen/ripple-component.js';

const {
  createDatabase,
  currentRevision,
  createInput,
  createInputWithDurability,
  inputSet,
  inputGet,
  inputContains,
  createQuery,
  queryFetch,
  createIntern,
  createInternWithDurability,
  internValue,
  internLookup,
  createAccumulator,
  accumulatorPush,
  accumulatorGetForQuery,
  accumulatorClearAll,
} = ripple;

let passed = 0;
let failed = 0;

function assert(cond, msg) {
  if (!cond) {
    console.error(`FAIL: ${msg}`);
    failed++;
  } else {
    console.log(`PASS: ${msg}`);
    passed++;
  }
}

function assertEq(a, b, msg) {
  const as = JSON.stringify(a);
  const bs = JSON.stringify(b);
  if (as !== bs) {
    console.error(`FAIL: ${msg}\n  expected: ${bs}\n  actual:   ${as}`);
    failed++;
  } else {
    console.log(`PASS: ${msg}`);
    passed++;
  }
}

// ===== Test 1: Database creation =====
{
  const db = createDatabase();
  assert(db === 0, 'createDatabase returns handle 0');
  const rev = currentRevision(db);
  assert(rev === 1, 'initial revision is 1');
}

// ===== Test 2: Input set/get =====
{
  const db = createDatabase();
  const input = createInput(db);

  const rev1 = inputSet(db, input, 'name', { tag: 'val-str', val: 'Alice' });
  assert(rev1 > 0, 'inputSet returns positive revision');

  const val = inputGet(db, input, 'name');
  assertEq(val, { tag: 'val-str', val: 'Alice' }, 'inputGet returns set value');

  assert(inputContains(input, 'name'), 'inputContains returns true for existing key');
  assert(!inputContains(input, 'missing'), 'inputContains returns false for missing key');

  const rev2 = inputSet(db, input, 'age', { tag: 'val-int', val: 30 });
  assert(rev2 > rev1, 'second inputSet bumps revision');

  assertEq(inputGet(db, input, 'age'), { tag: 'val-int', val: 30 }, 'inputGet returns int value');
}

// ===== Test 3: Input with durability =====
{
  const db = createDatabase();
  const input = createInputWithDurability(db, 'high');
  inputSet(db, input, 'config', { tag: 'val-str', val: 'stable' });
  assertEq(inputGet(db, input, 'config'), { tag: 'val-str', val: 'stable' }, 'input with durability works');
}

// ===== Test 4: Input unchanged value =====
{
  const db = createDatabase();
  const input = createInput(db);
  const rev1 = inputSet(db, input, 'x', { tag: 'val-int', val: 42 });
  const rev2 = inputSet(db, input, 'x', { tag: 'val-int', val: 42 }); // same value
  assertEq(rev1, rev2, 'setting same value does not bump revision');
}

// ===== Test 5: Input null/bool/float values =====
{
  const db = createDatabase();
  const input = createInput(db);

  inputSet(db, input, 'null_val', { tag: 'val-null' });
  assertEq(inputGet(db, input, 'null_val'), { tag: 'val-null' }, 'null value roundtrips');

  inputSet(db, input, 'bool_val', { tag: 'val-bool', val: true });
  assertEq(inputGet(db, input, 'bool_val'), { tag: 'val-bool', val: true }, 'bool value roundtrips');

  inputSet(db, input, 'float_val', { tag: 'val-float', val: 3.14 });
  assertEq(inputGet(db, input, 'float_val'), { tag: 'val-float', val: 3.14 }, 'float value roundtrips');
}

// ===== Test 6: Query with simple callback (no re-entrancy) =====
{
  const db = createDatabase();
  const input = createInput(db);
  inputSet(db, input, 'x', { tag: 'val-int', val: 10 });

  // Simple handler that returns a fixed value (no re-entrant calls)
  setComputeImpl((_queryId, key) => {
    return { tag: 'val-int', val: key.length * 10 };
  });

  const query = createQuery(db);
  const result = queryFetch(db, query, 'x');
  assertEq(result, { tag: 'val-int', val: 10 }, 'query callback returns computed value');

  // Cached result
  const result2 = queryFetch(db, query, 'x');
  assertEq(result2, { tag: 'val-int', val: 10 }, 'query returns cached result');
}

// ===== Test 7: Query caching (host-side state change does NOT trigger recomputation) =====
// The compute callback is opaque to ripple's dependency tracking,
// so host-side state changes don't invalidate the query cache.
{
  const db = createDatabase();
  const hostState = { y: 5 };

  setComputeImpl((_queryId, key) => {
    if (key in hostState) {
      return { tag: 'val-int', val: hostState[key] * 2 };
    }
    return { tag: 'val-null' };
  });

  const query = createQuery(db);
  const result1 = queryFetch(db, query, 'y');
  assertEq(result1, { tag: 'val-int', val: 10 }, 'initial query with host state');

  // Host-side state changes are invisible to ripple's dependency tracker
  hostState.y = 7;
  const input = createInput(db);
  inputSet(db, input, 'y', { tag: 'val-int', val: 7 });

  // Query returns cached result because compute callback has no tracked dependencies
  const result2 = queryFetch(db, query, 'y');
  assertEq(result2, { tag: 'val-int', val: 10 }, 'query returns cached value (no tracked deps)');
}

// ===== Test 8: Intern =====
{
  const db = createDatabase();
  const intern = createIntern(db);

  const id1 = internValue(db, intern, { tag: 'val-str', val: 'hello' });
  const id2 = internValue(db, intern, { tag: 'val-str', val: 'hello' }); // same value
  assertEq(id1, id2, 'interning same value returns same id');

  const id3 = internValue(db, intern, { tag: 'val-str', val: 'world' });
  assert(id3 !== id1, 'interning different value returns different id');

  assertEq(internLookup(db, intern, id1), { tag: 'val-str', val: 'hello' }, 'intern lookup returns original value');
  assertEq(internLookup(db, intern, id3), { tag: 'val-str', val: 'world' }, 'intern lookup for second value');
  assertEq(internLookup(db, intern, 999), undefined, 'intern lookup for invalid id returns undefined');
}

// ===== Test 9: Intern with durability =====
{
  const db = createDatabase();
  const intern = createInternWithDurability(db, 'medium');
  const id = internValue(db, intern, { tag: 'val-int', val: 42 });
  assertEq(internLookup(db, intern, id), { tag: 'val-int', val: 42 }, 'intern with durability works');
}

// ===== Summary =====
console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
