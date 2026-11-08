DekuContainerWrite::to_slice returns the incorrect number of bytes written as of 0.19.1
Deku now incorrectly calculates the number of bits written, and this error is cumulative. This can be seen when you compare the difference between the size of `to_bytes()` and the return value of `to_slice()` - this was fine in 0.18.1. Unsure about 0.18.0.

Repro cases:

<details>
<summary>Test code being used for all (with variations for fields)</summary>

```rs
#[cfg(test)]
mod test {
    use super::*;
    use deku::DekuContainerWrite;

    #[test]
    fn test_encode_size_eq() {
        let data = Test {
            a: 7,
            b: 1,
            c: 3,
        };

        let d = data.to_bytes().unwrap();
        let mut dd = vec![0u8; d.len()];
        let written = data.to_slice(&mut dd).unwrap();
        dbg!(&*dd);
        assert_eq!(d, dd, "Data does not match");
        assert_eq!(written, d.len(), "Size does not match");
    }
}
```
</details>

Works:
```rs
#[derive(DekuWrite)]
pub struct Test {
    a: u8,
}

#[derive(DekuWrite)]
pub struct Test {
    #[deku(bits = 3)]
    a: u8,
}

#[derive(DekuWrite)]
pub struct Test {
    #[deku(bits = 8)]
    a: u8,
    b: u8
}

#[derive(DekuWrite)]
pub struct Test {
    #[deku(bits = 3)]
    a: u8,
    #[deku(bits = 3)]
    b: u8,
}
```

Broken:
```rs
// Reports as 1 byte written (not 2)
#[derive(DekuWrite)]
pub struct Test {
    #[deku(bits = 8)]
    a: u8,
    #[deku(bits = 8)]
    b: u8,
}

// Reports as 1 byte written (not 2)
#[derive(DekuWrite)]
pub struct Test {
    #[deku(bits = 3)]
    a: u8,
    b: u8,
}

// Reports as 1 byte written (not 2)
#[derive(DekuWrite)]
pub struct Test {
    #[deku(bits = 3)]
    a: u8,
    #[deku(bits = 7)]
    b: u8,
}

// Reports as 1 byte written (not 3)
#[derive(DekuWrite)]
pub struct Test {
    #[deku(bits = 3)]
    a: u8,
    #[deku(bits = 6)]
    b: u8,
    c: u8,
}
```

<details>
<summary>Extra info with logs, for help debugging</summary>

This was with a struct shaped like
```rs
#[derive(DekuWrite)]
pub struct Test {
    #[deku(bits = 3)]
    a: u8,
    #[deku(bits = 7)]
    b: u8,
    c: u8,
}
```
and initialized as
```rs
Test {
    a: 0b011,
    b: 0b11010,
    c: 0b01010110,
};
```
to try and get a distinct bit pattern:

```
Writing: Test.a
attempting 3 bits : [0, 1, 1]
no write: msb pre-pending 3 bits : [0, 1, 1] => [0, 1, 1]
Writing: Test.b
attempting 7 bits : [0, 0, 1, 1, 0, 1, 0]
msb pre-pending 3 bits : [0, 1, 1]
now 10 bits : [0, 1, 1, 0, 0, 1, 1, 0, 1, 0]
msb: wrote 8 bits : 0x[66]
leftover 2 bits : [1, 0]
Writing: Test.c
writing 1 bytes
leftover exists
attempting 8 bits : [0, 1, 0, 1, 0, 1, 1, 0]
msb pre-pending 2 bits : [1, 0]
now 10 bits : [1, 0, 0, 1, 0, 1, 0, 1, 1, 0]
msb: wrote 8 bits : 0x[95]
leftover 2 bits : [1, 0]
finalized: 2 bits leftover
finalized: wrote 8 bits
```

data is [102, 149, 128]
Length is reported as 1, to vec reports as 3.

</details>

This error accumulates with more items. Using separate enums with defined sizes vs attributes on members doesn't affect the result.
The data is actually written correctly - even in my own production code (reports as 21 bytes written when 28 were actually written) - but the reported written size is mismatched.
