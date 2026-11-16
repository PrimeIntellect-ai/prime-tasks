builtin macros split expressions on comma within generic args
Cut from #6975.

It is very possible that I am screwing something up (since I am new to Rust and new to rusqlite and its doc is a bit lacking), but nevertheless I get red alert on code which compiles in cargo.

Here's a small compiling version:

```rust
use rusqlite::{Connection};
fn main() {

    let conn = Connection::open( "test.sql" ).expect( &format!("Fail to open db") );
    let mut sth = conn.prepare( "SELECT id,a1,a2,a3,a4,a5,a6,a7 FROM table WHERE name=?1" ).unwrap();

    let mut rows = match sth.query( &[ &"joe" ] ) {
        Ok(r) => r,
        Err(e) => { panic!("Cannot retrieve record: {:?}", &e); }
    };

    loop {
        let r = rows.next();
        match r {
            None => break ,
            Some(r) => match r {
                Err(e) => { panic!("Error retrieving row: {}", e) }
                Ok(r) => {
                    println!( "{:20} {:<10}  {:>20}→{:>20} {:15} {:15}⇒{:15} {:15} {:20} (c{})",
                        r.get::<usize,String>(5), r.get::<usize,String>(1),
                        r.get::<usize,String>(2), r.get::<usize,String>(6),
                        r.get::<usize,String>(3), r.get::<usize,String>(4), r.get::<usize,String>(7), r.get::<usize,String>(8), r.get::<usize,String>(9), r.get::<usize,String>(10)
                    );
                }
            }
        }
    }
}
```

I get complaints for "r.get::<usize".

My fragment behave pretty diferently [in playground](https://play.rust-lang.org/?version=stable&mode=debug&edition=2018&gist=15c5b21bc32bcdc24c5fb37eb41535d0): in my version Row.next() gives `Option<Result<Row, Error>>` while playground get the (way more possibly correct) `Result<Option<&Row<'_>>` and thus fails to build.

[update]
Aww. rusqlite v0.6.0 vs v0.24.0. Former uses the "old bad" result, my code used that. Now I upgraded my local version to the one playground uses and the result magically reversed (result->option->row). So my version worked under 0.6.0 and gave the error there. I'll rewrite to see how it behaves under new one.

(If you happen to be available on Matrix then I'm sitting in the Rust room, if you'd like to do some transient chat/questions.)
