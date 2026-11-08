Identifier allows zero scalar
Hello, I've noticed that recently the serialisation of the Identifier structure allows for a zero scalar. For example, the following:

```rust
    let arr: [u8; 32] = [0; 32];
    let id_result = frost::Identifier::deserialize(&arr);
    match id_result {
        Ok(_) => println!("got result"),
        Err(e) => println!("got error: {}", e),
    }

```

Produces "got result" on the 908289d commit.
