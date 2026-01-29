use criterion::{black_box, criterion_group, criterion_main, Criterion};
use salsa::{Database, Setter};

// Define a salsa database
#[salsa::input]
struct Input {
    #[return_ref]
    key: String,
    value: i32,
}

#[salsa::tracked]
fn compute_square(db: &dyn Database, input: Input) -> i32 {
    let v = input.value(db);
    v * v
}

#[salsa::tracked]
fn query_chain_1(db: &dyn Database, input: Input) -> i32 {
    input.value(db) + 1
}

#[salsa::tracked]
fn query_chain_2(db: &dyn Database, input: Input) -> i32 {
    query_chain_1(db, input) * 2
}

#[salsa::tracked]
fn query_chain_3(db: &dyn Database, input: Input) -> i32 {
    query_chain_2(db, input) + 10
}

#[salsa::db]
#[derive(Default, Clone)]
struct Db {
    storage: salsa::Storage<Self>,
}

#[salsa::db]
impl salsa::Database for Db {
    fn salsa_event(&self, _event: &dyn Fn() -> salsa::Event) {}
}

fn bench_query_cache_hit(c: &mut Criterion) {
    let db = Db::default();
    let input = Input::new(&db, "x".to_string(), 42);

    // Warm up cache
    let _ = compute_square(&db, input);

    c.bench_function("Query::fetch cache hit (1000 iterations)", |b| {
        b.iter(|| {
            for _ in 0..1000 {
                black_box(compute_square(&db, input));
            }
        })
    });
}

fn bench_query_recompute(c: &mut Criterion) {
    let mut db = Db::default();
    let input = Input::new(&db, "x".to_string(), 0);

    c.bench_function("Query::fetch recompute (100 iterations)", |b| {
        b.iter(|| {
            for i in 0..100 {
                input.set_value(&mut db).to(i);
                black_box(compute_square(&db, input));
            }
        })
    });
}

fn bench_chained_queries(c: &mut Criterion) {
    let db = Db::default();
    let input = Input::new(&db, "x".to_string(), 5);

    // Warm up
    let _ = query_chain_3(&db, input);

    c.bench_function("Chained queries (3 levels) cache hit (1000 iterations)", |b| {
        b.iter(|| {
            for _ in 0..1000 {
                black_box(query_chain_3(&db, input));
            }
        })
    });
}

fn bench_many_keys(c: &mut Criterion) {
    let db = Db::default();
    let inputs: Vec<_> = (0..1000)
        .map(|i| Input::new(&db, format!("key_{}", i), i))
        .collect();

    // Warm up
    for input in &inputs {
        let _ = compute_square(&db, *input);
    }

    c.bench_function("Query::fetch 1000 different keys (cached)", |b| {
        b.iter(|| {
            for input in &inputs {
                black_box(compute_square(&db, *input));
            }
        })
    });
}

fn bench_backdate(c: &mut Criterion) {
    let mut db = Db::default();
    let input = Input::new(&db, "x".to_string(), 1);

    // Query that returns constant regardless of input
    #[salsa::tracked]
    fn constant_query(db: &dyn Database, input: Input) -> i32 {
        let _ = input.value(db); // Read input to create dependency
        42 // Always return 42
    }

    let _ = constant_query(&db, input);

    c.bench_function("Backdate (same result recompute, 100 iterations)", |b| {
        b.iter(|| {
            for i in 0..100 {
                input.set_value(&mut db).to(i);
                black_box(constant_query(&db, input));
            }
        })
    });
}

criterion_group!(
    benches,
    bench_query_cache_hit,
    bench_query_recompute,
    bench_chained_queries,
    bench_many_keys,
    bench_backdate,
);
criterion_main!(benches);
