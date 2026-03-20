///|
/// Handle storage
let databases : Array[@ripple.Database] = []

///|
let inputs : Array[@ripple.Input[String, Value]] = []

///|
let queries : Array[@ripple.Query[String, Value]] = []

///|
let interns : Array[@ripple.Intern[Value]] = []

///|
let accumulators : Array[@ripple.Accumulator[Value]] = []

///|
/// Map from query array index to database array index
let query_db_map : Array[Int] = []

///|
/// Map from input array index to database array index
let input_db_map : Array[Int] = []

///|
/// Map from intern array index to database array index
let intern_db_map : Array[Int] = []

///|
/// Map from accumulator array index to database array index
let acc_db_map : Array[Int] = []

// -- Hash implementation for Value (needed by Intern) --

///|
impl Hash for Value with hash(self) -> Int {
  match self {
    ValNull => 0
    ValBool(b) => if b { 1 } else { 2 }
    ValInt(i) => i * 31 + 3
    ValFloat(f) => f.reinterpret_as_int64().to_int() * 31 + 4
    ValStr(s) => s.hash() * 31 + 5
  }
}

///|
impl Hash for Value with hash_combine(self, hasher) {
  hasher.combine_int(self.hash())
}

// -- Conversion: import Value ↔ export Value --

///|
fn from_qh_value(v : @query_handler.Value) -> Value {
  match v {
    ValNull => ValNull
    ValBool(b) => ValBool(b)
    ValInt(i) => ValInt(i)
    ValFloat(f) => ValFloat(f)
    ValStr(s) => ValStr(s)
  }
}

// -- Conversion: WIT Durability ↔ ripple Durability --

///|
fn wit_to_durability(d : Durability) -> @ripple.Durability {
  match d {
    Low => @ripple.Durability::Low
    Medium => @ripple.Durability::Medium
    High => @ripple.Durability::High
  }
}

// ========== Database API ==========

///|
fn create_database() -> UInt {
  let db = @ripple.Database::new()
  databases.push(db)
  (databases.length() - 1).reinterpret_as_uint()
}

///|
fn current_revision(db : UInt) -> Int {
  let d = db.reinterpret_as_int()
  databases[d].current_revision().get()
}

// ========== Input API ==========

///|
fn create_input(db : UInt) -> UInt {
  let d = db.reinterpret_as_int()
  let input : @ripple.Input[String, Value] = databases[d].input()
  input.register(databases[d].runtime())
  inputs.push(input)
  input_db_map.push(d)
  (inputs.length() - 1).reinterpret_as_uint()
}

///|
fn create_input_with_durability(db : UInt, dur : Durability) -> UInt {
  let d = db.reinterpret_as_int()
  let input : @ripple.Input[String, Value] = databases[d].input_with_durability(
    wit_to_durability(dur),
  )
  input.register(databases[d].runtime())
  inputs.push(input)
  input_db_map.push(d)
  (inputs.length() - 1).reinterpret_as_uint()
}

///|
fn input_set(db : UInt, input_handle : UInt, key : String, val : Value) -> Int {
  let d = db.reinterpret_as_int()
  let h = input_handle.reinterpret_as_int()
  let rev = inputs[h].set(databases[d].runtime(), key, val)
  rev.get()
}

///|
fn input_get(db : UInt, input_handle : UInt, key : String) -> Value? {
  let d = db.reinterpret_as_int()
  let h = input_handle.reinterpret_as_int()
  inputs[h].get(databases[d].runtime(), key)
}

///|
fn input_contains(input_handle : UInt, key : String) -> Int {
  let h = input_handle.reinterpret_as_int()
  if inputs[h].contains(key) {
    1
  } else {
    0
  }
}

// ========== Query API ==========

///|
fn create_query(db : UInt) -> UInt {
  let d = db.reinterpret_as_int()
  let query_id = queries.length().reinterpret_as_uint()
  let compute = fn(_rt : @ripple.Runtime, key : String) -> Value {
    from_qh_value(@query_handler.compute(query_id, key))
  }
  let query : @ripple.Query[String, Value] = databases[d].query(compute)
  query.register(databases[d].runtime())
  queries.push(query)
  query_db_map.push(d)
  query_id
}

///|
fn query_fetch(db : UInt, query_handle : UInt, key : String) -> Value {
  let d = db.reinterpret_as_int()
  let h = query_handle.reinterpret_as_int()
  queries[h].fetch(databases[d].runtime(), key)
}

// ========== Intern API ==========

///|
fn create_intern(db : UInt) -> UInt {
  let d = db.reinterpret_as_int()
  let intern : @ripple.Intern[Value] = databases[d].intern()
  intern.register(databases[d].runtime())
  interns.push(intern)
  intern_db_map.push(d)
  (interns.length() - 1).reinterpret_as_uint()
}

///|
fn create_intern_with_durability(db : UInt, dur : Durability) -> UInt {
  let d = db.reinterpret_as_int()
  let intern : @ripple.Intern[Value] = databases[d].intern_with_durability(
    wit_to_durability(dur),
  )
  intern.register(databases[d].runtime())
  interns.push(intern)
  intern_db_map.push(d)
  (interns.length() - 1).reinterpret_as_uint()
}

///|
fn intern_value(db : UInt, intern_handle : UInt, val : Value) -> Int {
  let d = db.reinterpret_as_int()
  let h = intern_handle.reinterpret_as_int()
  interns[h].intern(databases[d].runtime(), val).get()
}

///|
fn intern_lookup(db : UInt, intern_handle : UInt, id : Int) -> Value? {
  let d = db.reinterpret_as_int()
  let h = intern_handle.reinterpret_as_int()
  interns[h].lookup(databases[d].runtime(), @ripple.InternId::from_raw(id))
}

// ========== Accumulator API ==========

///|
fn create_accumulator(db : UInt) -> UInt {
  let d = db.reinterpret_as_int()
  let acc : @ripple.Accumulator[Value] = databases[d].accumulator()
  accumulators.push(acc)
  acc_db_map.push(d)
  (accumulators.length() - 1).reinterpret_as_uint()
}

///|
fn accumulator_push(db : UInt, acc_handle : UInt, val : Value) -> Unit {
  let d = db.reinterpret_as_int()
  let h = acc_handle.reinterpret_as_int()
  accumulators[h].push(databases[d].runtime(), val)
}

///|
fn accumulator_get_for_query(
  acc_handle : UInt,
  query_handle : UInt,
  key : String,
) -> Array[Value] {
  let ah = acc_handle.reinterpret_as_int()
  let qh = query_handle.reinterpret_as_int()
  accumulators[ah].get_for_query(queries[qh], key)
}

///|
fn accumulator_clear_all(acc_handle : UInt) -> Unit {
  let h = acc_handle.reinterpret_as_int()
  accumulators[h].clear_all()
}
