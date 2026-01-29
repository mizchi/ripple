///|
/// Simple S-expression based typed language for incremental type checking demo
///
/// Syntax:
///   expr ::= num | bool | var | (let var expr expr) | (fn var type expr) | (app expr expr) | (if expr expr expr)
///   type ::= Int | Bool | (-> type type)
///
/// Example:
///   (let x 10 (app inc x))
///   (fn n Int (if (app is_zero n) 0 (app inc n)))

///|
/// Types in our language
enum Ty {
  TInt
  TBool
  TFun(Ty, Ty)
  TError(String)
} derive(Eq, Show)

///|
/// Expressions (simplified AST)
enum Expr {
  ENum(Int)
  EBool(Bool)
  EVar(String)
  ELet(String, Expr, Expr)
  EFn(String, Ty, Expr)
  EApp(Expr, Expr)
  EIf(Expr, Expr, Expr)
} derive(Eq, Show)

///|
/// Type environment
struct TyEnv {
  bindings : @hashmap.HashMap[String, Ty]
}

///|
fn TyEnv::new() -> TyEnv {
  { bindings: @hashmap.new() }
}

///|
fn TyEnv::extend(self : TyEnv, name : String, ty : Ty) -> TyEnv {
  let new_bindings : @hashmap.HashMap[String, Ty] = @hashmap.new()
  for entry in self.bindings.iter() {
    let (k, v) = entry
    new_bindings.set(k, v)
  }
  new_bindings.set(name, ty)
  { bindings: new_bindings }
}

///|
fn TyEnv::lookup(self : TyEnv, name : String) -> Ty? {
  self.bindings.get(name)
}

///|
/// Type check an expression
fn type_check(env : TyEnv, expr : Expr) -> Ty {
  match expr {
    ENum(_) => TInt
    EBool(_) => TBool
    EVar(name) =>
      match env.lookup(name) {
        Some(ty) => ty
        None => TError("Unbound variable: " + name)
      }
    ELet(name, value, body) => {
      let value_ty = type_check(env, value)
      match value_ty {
        TError(_) => value_ty
        _ => {
          let new_env = env.extend(name, value_ty)
          type_check(new_env, body)
        }
      }
    }
    EFn(param, param_ty, body) => {
      let new_env = env.extend(param, param_ty)
      let body_ty = type_check(new_env, body)
      match body_ty {
        TError(_) => body_ty
        _ => TFun(param_ty, body_ty)
      }
    }
    EApp(func, arg) => {
      let func_ty = type_check(env, func)
      let arg_ty = type_check(env, arg)
      match (func_ty, arg_ty) {
        (TError(_), _) => func_ty
        (_, TError(_)) => arg_ty
        (TFun(param_ty, ret_ty), _) =>
          if param_ty == arg_ty {
            ret_ty
          } else {
            TError(
              "Type mismatch: expected " +
              param_ty.to_string() +
              ", got " +
              arg_ty.to_string(),
            )
          }
        _ => TError("Not a function: " + func_ty.to_string())
      }
    }
    EIf(cond, then_branch, else_branch) => {
      let cond_ty = type_check(env, cond)
      match cond_ty {
        TBool => {
          let then_ty = type_check(env, then_branch)
          let else_ty = type_check(env, else_branch)
          match (then_ty, else_ty) {
            (TError(_), _) => then_ty
            (_, TError(_)) => else_ty
            _ =>
              if then_ty == else_ty {
                then_ty
              } else {
                TError(
                  "Branch type mismatch: " +
                  then_ty.to_string() +
                  " vs " +
                  else_ty.to_string(),
                )
              }
          }
        }
        TError(_) => cond_ty
        _ => TError("Condition must be Bool, got " + cond_ty.to_string())
      }
    }
  }
}

///|
/// Simple S-expression parser
fn parse_sexpr(input : String) -> Expr? {
  let tokens = tokenize(input)
  if tokens.is_empty() {
    return None
  }
  let (expr, _) = parse_tokens(tokens, 0)
  expr
}

///|
fn tokenize(input : String) -> Array[String] {
  let tokens : Array[String] = []
  let current : Array[Char] = []
  for c in input {
    if c == '(' || c == ')' {
      if not(current.is_empty()) {
        tokens.push(String::from_array(current))
        current.clear()
      }
      tokens.push(c.to_string())
    } else if c == ' ' || c == '\n' || c == '\t' {
      if not(current.is_empty()) {
        tokens.push(String::from_array(current))
        current.clear()
      }
    } else {
      current.push(c)
    }
  }
  if not(current.is_empty()) {
    tokens.push(String::from_array(current))
  }
  tokens
}

///|
fn parse_tokens(tokens : Array[String], pos : Int) -> (Expr?, Int) {
  if pos >= tokens.length() {
    return (None, pos)
  }
  let token = tokens[pos]
  if token == "(" {
    // Parse compound expression
    if pos + 1 >= tokens.length() {
      return (None, pos)
    }
    let head = tokens[pos + 1]
    if head == "let" {
      // (let name value body)
      if pos + 3 >= tokens.length() {
        return (None, pos)
      }
      let name = tokens[pos + 2]
      let (value, next_pos) = parse_tokens(tokens, pos + 3)
      match value {
        Some(v) => {
          let (body, final_pos) = parse_tokens(tokens, next_pos)
          match body {
            Some(b) => (Some(ELet(name, v, b)), final_pos + 1) // skip )
            None => (None, final_pos)
          }
        }
        None => (None, next_pos)
      }
    } else if head == "fn" {
      // (fn param type body)
      if pos + 4 >= tokens.length() {
        return (None, pos)
      }
      let param = tokens[pos + 2]
      let ty_str = tokens[pos + 3]
      let param_ty = parse_type(ty_str)
      let (body, final_pos) = parse_tokens(tokens, pos + 4)
      match body {
        Some(b) => (Some(EFn(param, param_ty, b)), final_pos + 1)
        None => (None, final_pos)
      }
    } else if head == "app" {
      // (app func arg)
      let (func, next_pos) = parse_tokens(tokens, pos + 2)
      match func {
        Some(f) => {
          let (arg, final_pos) = parse_tokens(tokens, next_pos)
          match arg {
            Some(a) => (Some(EApp(f, a)), final_pos + 1)
            None => (None, final_pos)
          }
        }
        None => (None, next_pos)
      }
    } else if head == "if" {
      // (if cond then else)
      let (cond, pos1) = parse_tokens(tokens, pos + 2)
      match cond {
        Some(c) => {
          let (then_b, pos2) = parse_tokens(tokens, pos1)
          match then_b {
            Some(t) => {
              let (else_b, pos3) = parse_tokens(tokens, pos2)
              match else_b {
                Some(e) => (Some(EIf(c, t, e)), pos3 + 1)
                None => (None, pos3)
              }
            }
            None => (None, pos2)
          }
        }
        None => (None, pos1)
      }
    } else {
      (None, pos)
    }
  } else if token == ")" {
    (None, pos)
  } else if token == "true" {
    (Some(EBool(true)), pos + 1)
  } else if token == "false" {
    (Some(EBool(false)), pos + 1)
  } else {
    // Try to parse as number
    match try_parse_int(token) {
      Some(n) => (Some(ENum(n)), pos + 1)
      None => (Some(EVar(token)), pos + 1)
    }
  }
}

///|
fn parse_type(s : String) -> Ty {
  if s == "Int" {
    TInt
  } else if s == "Bool" {
    TBool
  } else {
    TError("Unknown type: " + s)
  }
}

///|
/// Try to parse a string as an integer
fn try_parse_int(s : String) -> Int? {
  if s.length() == 0 {
    return None
  }
  let chars = s.to_array()
  let mut result = 0
  let mut i = 0
  let mut negative = false
  if chars[0] == '-' {
    negative = true
    i = 1
  }
  while i < chars.length() {
    let c = chars[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
    i = i + 1
  }
  if negative {
    Some(-result)
  } else {
    Some(result)
  }
}

///|
/// Run the incremental type checking demo
pub fn run_typelang_demo() -> Unit {
  println("=== Incremental Type Checking Demo ===\n")
  // Create database
  let db = @ripple.Database::new()
  let rt = db.runtime()
  // Source code for each definition (Input)
  let sources : @ripple.Input[String, String] = db.input()
  sources.register(rt)
  // Type errors accumulator
  let errors : @ripple.Accumulator[String] = db.accumulator()
  // Parse definition (Query)
  let mut parse_count = 0
  let parse_def : @ripple.Query[String, Expr?] = db.query(fn(rt, name) {
    parse_count = parse_count + 1
    println("  [parse] " + name)
    match sources.get(rt, name) {
      Some(src) => parse_sexpr(src)
      None => {
        errors.push(rt, "Source not found: " + name)
        None
      }
    }
  })
  parse_def.register(rt)
  // Get type of a definition (Query)
  // Creates dependency on other definitions via env lookup
  let mut typecheck_count = 0
  let get_type : @ripple.Query[String, Ty] = db.query(fn(rt, name) {
    typecheck_count = typecheck_count + 1
    println("  [typecheck] " + name)
    match parse_def.fetch(rt, name) {
      Some(expr) => {
        // Build environment from other definitions
        // For simplicity, we use a predefined set of builtins
        let env = TyEnv::new()
          .extend("inc", TFun(TInt, TInt))
          .extend("dec", TFun(TInt, TInt))
          .extend("is_zero", TFun(TInt, TBool))
          .extend("add", TFun(TInt, TFun(TInt, TInt)))
        let ty = type_check(env, expr)
        match ty {
          TError(msg) => errors.push(rt, name + ": " + msg)
          _ => ()
        }
        ty
      }
      None => TError("Parse failed")
    }
  })
  get_type.register(rt)
  // ========================================
  // Scenario 1: Initial type check
  // ========================================
  println("--- Scenario 1: Initial Type Check ---")
  // double: Int -> Int (applies inc twice)
  sources.set(rt, "double", "(fn x Int (app inc (app inc x)))") |> ignore
  // main: let binding with inc
  sources.set(rt, "main", "(let n 10 (app inc n))") |> ignore
  // helper: Bool -> Int
  sources.set(rt, "helper", "(fn b Bool (if b 1 0))") |> ignore
  parse_count = 0
  typecheck_count = 0
  let ty1 = get_type.fetch(rt, "main")
  let ty2 = get_type.fetch(rt, "double")
  let ty3 = get_type.fetch(rt, "helper")
  println("  main : " + ty1.to_string())
  println("  double : " + ty2.to_string())
  println("  helper : " + ty3.to_string())
  println("  Parse calls: " + parse_count.to_string())
  println("  Typecheck calls: " + typecheck_count.to_string())
  println("")
  // ========================================
  // Scenario 2: No changes - all cached
  // ========================================
  println("--- Scenario 2: Re-check (no changes) ---")
  parse_count = 0
  typecheck_count = 0
  let ty1b = get_type.fetch(rt, "main")
  let ty2b = get_type.fetch(rt, "double")
  let ty3b = get_type.fetch(rt, "helper")
  println("  main : " + ty1b.to_string())
  println("  double : " + ty2b.to_string())
  println("  helper : " + ty3b.to_string())
  println("  Parse calls: " + parse_count.to_string() + " (cached!)")
  println("  Typecheck calls: " + typecheck_count.to_string() + " (cached!)")
  println("")
  // ========================================
  // Scenario 3: Change helper (independent)
  // ========================================
  println("--- Scenario 3: Change helper (independent) ---")
  sources.set(rt, "helper", "(fn b Bool (if b 100 0))") |> ignore
  parse_count = 0
  typecheck_count = 0
  let ty1c = get_type.fetch(rt, "main")
  let ty2c = get_type.fetch(rt, "double")
  let ty3c = get_type.fetch(rt, "helper")
  println("  main : " + ty1c.to_string())
  println("  double : " + ty2c.to_string())
  println("  helper : " + ty3c.to_string())
  println("  Parse calls: " + parse_count.to_string() + " (only helper)")
  println(
    "  Typecheck calls: " + typecheck_count.to_string() + " (only helper)",
  )
  println("")
  // ========================================
  // Scenario 4: Change main only
  // ========================================
  println("--- Scenario 4: Change main ---")
  sources.set(rt, "main", "(let n 20 (app inc n))") |> ignore
  parse_count = 0
  typecheck_count = 0
  let ty1d = get_type.fetch(rt, "main")
  println("  main : " + ty1d.to_string())
  println("  Parse calls: " + parse_count.to_string())
  println("  Typecheck calls: " + typecheck_count.to_string())
  println("")
  // ========================================
  // Scenario 5: Introduce type error
  // ========================================
  println("--- Scenario 5: Introduce type error ---")
  sources.set(rt, "broken", "(app inc true)") |> ignore // Type error!
  parse_count = 0
  typecheck_count = 0
  let ty_broken = get_type.fetch(rt, "broken")
  println("  broken : " + ty_broken.to_string())
  let broken_errors = errors.get_for_query(get_type, "broken")
  for err in broken_errors {
    println("  Error: " + err)
  }
  println("  Parse calls: " + parse_count.to_string())
  println("  Typecheck calls: " + typecheck_count.to_string())
  println("")
  // ========================================
  // Scenario 6: Fix the error
  // ========================================
  println("--- Scenario 6: Fix the error ---")
  sources.set(rt, "broken", "(app inc 42)") |> ignore
  parse_count = 0
  typecheck_count = 0
  let ty_fixed = get_type.fetch(rt, "broken")
  println("  broken : " + ty_fixed.to_string())
  println("  Parse calls: " + parse_count.to_string())
  println("  Typecheck calls: " + typecheck_count.to_string())
  println("")
  // ========================================
  // Summary
  // ========================================
  println("=== Summary ===")
  println("The incremental type checker demonstrates:")
  println("  1. Parse results are cached per definition")
  println("  2. Type check results are cached")
  println("  3. Changing one definition only re-checks that definition")
  println("  4. Independent definitions don't affect each other")
  println("  5. Errors are accumulated and tracked per query")
}
