Inconsistencies in floating point parsing
Grammar taken from [current master](https://github.com/ron-rs/ron/blob/3ec0dc09f9b557d73790b9916b0d5cc4cc0f4c3d/docs/grammar.md). There are a couple inconcistencies between the grammar, the current implementation, and from how rust does it.

1. Exponential notation. The grammar allows `1.0e1`, but disallows `1e1` and bizzarely disallows sign: `1.0e+1` and `1.0e-1`. But the implementation accepts all those forms, and so does rust.

2. Underscores are disallowed in floats, and this is consistent in both the grammar and the implementation; but it differs from rust and is a bit unexpected.

Here's small repro for everything:
```rust
type R<T> = ron::Result<T>;

fn main() {
    let x1: R<i64> = ron::from_str("1_0");
    println!("{:?}", &x1);
    // >>> Ok(10)

    let x2: R<f64> = ron::from_str("1_0.1_0");
    println!("{:?}", &x2);
    // >>> Err(Error { code: TrailingCharacters, position: Position { line: 1, col: 2 } })

    let x3: R<f64> = ron::from_str("1_0.10");
    println!("{:?}", &x3);
    // >>> Err(Error { code: TrailingCharacters, position: Position { line: 1, col: 2 } })

    let x4: R<f64> = ron::from_str("10.1_0");
    println!("{:?}", &x4);
    // >>> Err(Error { code: TrailingCharacters, position: Position { line: 1, col: 5 } })

    let x5: R<f64> = ron::from_str("1.0e-1");
    println!("{:?}", &x5);
    // >>> Ok(10.1)

    let y1: R<f64> = ron::from_str("1.0e1");
    println!("{:?}", &y1);
    // >>> Ok(10.0)

    let y2: R<f64> = ron::from_str("1e1");
    println!("{:?}", &y2);
    // >>> Ok(10.0)

    let y3: R<f64> = ron::from_str("1.0e1.0");
    println!("{:?}", &y3);
    // >>> Err(Error { code: ExpectedFloat, position: Position { line: 1, col: 1 } })

    let y4: R<f64> = ron::from_str("1.0e+1");
    println!("{:?}", &y4);
    // >>> Ok(10.0)

    let y5: R<f64> = ron::from_str("1.0e-1");
    println!("{:?}", &y5);
    // >>> Ok(0.1)
}
// y3 being Err is alright I believe, but the error message is weird
```

### Additional contract requirements

The documented float grammar must allow an exponent on an integer mantissa and must allow either `+` or `-` as an optional exponent sign.
