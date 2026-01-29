# ripple 使用例

変更が依存グラフを波紋のように伝播し、必要な部分だけ再計算するインクリメンタル計算ライブラリ。

## 基本的な使い方

### Database と Runtime の作成

```mbt check
///|
test {
  let db = Database::new()
  let _rt = db.runtime()
  inspect(db.current_revision().get(), content="1")
}
```

### Input: 外部入力の管理

Input は外部からの入力値を管理します。値が変更されると Revision が進みます。

```mbt check
///|
test {
  let db = Database::new()
  let rt = db.runtime()

  // Input の作成と登録
  let files : Input[String, String] = db.input()
  files.register(rt)

  // 値の設定
  files.set(rt, "main.mbt", "fn main { }") |> ignore
  files.set(rt, "lib.mbt", "fn helper { }") |> ignore

  // 値の取得
  inspect(files.get(rt, "main.mbt"), content="Some(\"fn main { }\")")
  inspect(files.get(rt, "lib.mbt"), content="Some(\"fn helper { }\")")
  inspect(files.get(rt, "unknown"), content="None")
}
```

### Query: メモ化されたクエリ

Query は純粋関数をメモ化します。依存する Input が変更されない限り、キャッシュが再利用されます。

```mbt check
///|
test {
  let db = Database::new()
  let rt = db.runtime()
  let numbers : Input[String, Int] = db.input()
  numbers.register(rt)

  // 計算回数をカウント
  let mut count = 0
  let double : Query[String, Int] = db.query(fn(rt, key) {
    count = count + 1
    match numbers.get(rt, key) {
      Some(n) => n * 2
      None => 0
    }
  })
  double.register(rt)

  // 入力を設定
  numbers.set(rt, "x", 10) |> ignore

  // 初回は計算される
  inspect(double.fetch(rt, "x"), content="20")
  inspect(count, content="1")

  // 2回目はキャッシュから返される
  inspect(double.fetch(rt, "x"), content="20")
  inspect(count, content="1") // カウントは増えない

  // 入力を変更すると再計算される
  numbers.set(rt, "x", 25) |> ignore
  inspect(double.fetch(rt, "x"), content="50")
  inspect(count, content="2")
}
```

### クエリの連鎖

クエリは他のクエリに依存できます。依存グラフが自動的に追跡されます。

```mbt check
///|
test {
  let db = Database::new()
  let rt = db.runtime()
  let values : Input[String, Int] = db.input()
  values.register(rt)

  // 値を2倍にするクエリ
  let double : Query[String, Int] = db.query(fn(rt, key) {
    match values.get(rt, key) {
      Some(n) => n * 2
      None => 0
    }
  })
  double.register(rt)

  // double の結果をさらに2倍にするクエリ
  let quadruple : Query[String, Int] = db.query(fn(rt, key) {
    double.fetch(rt, key) * 2
  })
  quadruple.register(rt)
  values.set(rt, "n", 5) |> ignore
  inspect(double.fetch(rt, "n"), content="10")
  inspect(quadruple.fetch(rt, "n"), content="20")
}
```

## 高度な機能

### CycleQuery: 循環依存の処理

再帰的なクエリには CycleQuery を使います。循環検出時のフォールバック値を指定できます。

```mbt check
///|
test {
  let db = Database::new()
  let rt = db.runtime()

  // フィボナッチ数列（循環参照あり）
  let fib_ref : Ref[CycleQuery[Int, Int]?] = { val: None }
  let fib : CycleQuery[Int, Int] = db.cycle_query_with_fallback(
    fn(rt, n) {
      if n <= 1 {
        n
      } else {
        let self = fib_ref.val.unwrap()
        self.fetch(rt, n - 1) + self.fetch(rt, n - 2)
      }
    },
    0, // 循環時のフォールバック値
  )
  fib_ref.val = Some(fib)
  fib.register(rt)
  inspect(fib.fetch(rt, 0), content="0")
  inspect(fib.fetch(rt, 1), content="1")
  inspect(fib.fetch(rt, 5), content="5")
  inspect(fib.fetch(rt, 10), content="55")
}
```

### Intern: 値の重複排除

同じ値に対して一意の ID を割り当てます。文字列のインターニングなどに使用します。

```mbt check
///|
test {
  let db = Database::new()
  let rt = db.runtime()
  let strings : Intern[String] = db.intern()
  strings.register(rt)

  // 同じ文字列は同じ ID になる
  let id1 = strings.intern(rt, "hello")
  let id2 = strings.intern(rt, "world")
  let id3 = strings.intern(rt, "hello")
  inspect(id1 == id3, content="true") // 同じ値 → 同じ ID
  inspect(id1 == id2, content="false") // 違う値 → 違う ID

  // ID から値を逆引き
  inspect(strings.lookup(rt, id1), content="Some(\"hello\")")
  inspect(strings.lookup(rt, id2), content="Some(\"world\")")
}
```

### Accumulator: 副作用データの収集

クエリ実行中に診断情報やログを収集できます。

```mbt check
///|
test {
  let db = Database::new()
  let rt = db.runtime()
  let code : Input[String, String] = db.input()
  code.register(rt)

  // 警告を収集する Accumulator
  let warnings : Accumulator[String] = db.accumulator()

  // コードをチェックするクエリ
  let check : Query[String, Bool] = db.query(fn(rt, name) {
    match code.get(rt, name) {
      Some(content) => {
        if content.contains("TODO") {
          warnings.push(rt, "TODO comment found in " + name)
        }
        if content.contains("FIXME") {
          warnings.push(rt, "FIXME comment found in " + name)
        }
        true
      }
      None => false
    }
  })
  code.set(rt, "main", "fn main { } // TODO: implement") |> ignore
  check.fetch(rt, "main") |> ignore

  // クエリに関連付けられた警告を取得
  let main_warnings = warnings.get_for_query(check, "main")
  inspect(main_warnings.length(), content="1")
  inspect(main_warnings[0], content="TODO comment found in main")
}
```

### Durability: 変更頻度の指定

入力の変更頻度を指定することで、検証をスキップして最適化できます。

```mbt check
///|
test {
  let db = Database::new()
  let rt = db.runtime()

  // 頻繁に変更される入力（デフォルト）
  let user_files : Input[String, String] = db.input()
  user_files.register(rt)

  // ほとんど変更されない入力（ライブラリなど）
  let stdlib : Input[String, String] = db.input_with_durability(
    Durability::High,
  )
  stdlib.register(rt)
  inspect(user_files.get_durability(), content="Low")
  inspect(stdlib.get_durability(), content="High")
}
```

## 実用例: インクリメンタルビルドシステム

```mbt check
///|
test {
  let db = Database::new()
  let rt = db.runtime()

  // ソースファイル
  let sources : Input[String, String] = db.input()
  sources.register(rt)

  // import 文を解析
  let parse_imports : Query[String, Array[String]] = db.query(fn(rt, path) {
    match sources.get(rt, path) {
      Some(content) => {
        let imports : Array[String] = []
        if content.contains("import a") {
          imports.push("a")
        }
        if content.contains("import b") {
          imports.push("b")
        }
        imports
      }
      None => []
    }
  })
  parse_imports.register(rt)

  // ファイルを設定
  sources.set(rt, "main", "import a\nimport b\nfn main {}") |> ignore
  sources.set(rt, "a", "fn helper_a {}") |> ignore
  sources.set(rt, "b", "import a\nfn helper_b {}") |> ignore

  // 依存関係を解析
  inspect(parse_imports.fetch(rt, "main"), content="[\"a\", \"b\"]")
  inspect(parse_imports.fetch(rt, "b"), content="[\"a\"]")
  inspect(parse_imports.fetch(rt, "a"), content="[]")
}
```
