Doc-Comment not resolving to field-names
**rust-analyzer version**: `0.3.1599-standalone`

**rustc version**: `rustc 1.71.0 (8ede3aae2 2023-07-12)`
**rustc version**: `rustc 1.73.0-nightly (ad963232d 2023-07-14)`

**relevant settings**: (eg. client settings, or environment variables like `CARGO`, `RUSTC`, `RUSTUP_HOME` or `CARGO_HOME`)
```jsonc
// related options from vscode settings
{
	"rust-analyzer.debug.openDebugPane": true,
	"rust-analyzer.rustfmt.extraArgs": [
		"+nightly"
	],
}
```

```txt
CARGO_HOME=/home/hasezoey/.local/cargo
CARGO_REGISTRIES_CRATES_IO_PROTOCOL=sparse
RUSTUP_HOME=/home/hasezoey/.local/rustup
```

using vscode 1.79.2

---

Currently rust-analyzer (vscode at least) does not resolve to field names, but `rustdoc` does

given the following code, rust-analyzer does not link anywhere
```rust
mod testy {
	pub struct Testy {
		pub field: String,
	}
}

/// Should resolve to field [testy::Testy::field] `test`
pub fn hello() {
	todo!();
}
```

trace:
```txt
[Trace - 1:39:36 PM] Received response 'textDocument/hover - (92)' in 1ms.
Result: {
    "contents": {
        "kind": "markdown",
        "value": "\n```rust\nmh\n```\n\n```rust\nfn hello()\n```\n\n---\n\nShould resolve to field [testy::Testy::field](testy::Testy::field) `test`"
    },
    "range": {
        "start": {
            "line": 7,
            "character": 3
        },
        "end": {
            "line": 7,
            "character": 8
        }
    }
}
```

![example1](https://github.com/rust-lang/rust-analyzer/assets/10911626/16c3dd20-05f4-40b3-acea-e216c58c1222)

without the field, it would generate trace:
```txt
[Trace - 1:41:08 PM] Received response 'textDocument/hover - (130)' in 1ms.
Result: {
    "contents": {
        "kind": "markdown",
        "value": "\n```rust\ntest\n```\n\n```rust\nfn hello()\n```\n\n---\n\nShould resolve to field [testy::Testy](https://docs.rs/test/0.0.1/test/testy/struct.Testy.html) `test`"
    },
    "range": {
        "start": {
            "line": 7,
            "character": 3
        },
        "end": {
            "line": 7,
            "character": 8
        }
    }
}
```

and adding in-line code-blocks, gives a result that would mark it as a link, but it is not openable, trace:
```txt
[Trace - 1:41:44 PM] Received response 'textDocument/hover - (186)' in 1ms.
Result: {
    "contents": {
        "kind": "markdown",
        "value": "\n```rust\ntest\n```\n\n```rust\nfn hello()\n```\n\n---\n\nShould resolve to field [`testy::Testy::field`](`testy::Testy::field`) `test`"
    },
    "range": {
        "start": {
            "line": 7,
            "character": 3
        },
        "end": {
            "line": 7,
            "character": 8
        }
    }
}
```

![example2](https://github.com/rust-lang/rust-analyzer/assets/10911626/149f72a1-210a-4db9-97f2-b68456fec7c0)

but in the end `rustdoc` resolves it just fine
![rustdoc](https://github.com/rust-lang/rust-analyzer/assets/10911626/c806bb4b-92eb-4489-a7f4-17dec051c79d)

---

PS: i originally came here to report a related issue, but i cannot reproduce it in a simpler example, issue being that rust-analyzer actually creates a openable link, but the link does not open:

![Screenshot_20230724_134752](https://github.com/rust-lang/rust-analyzer/assets/10911626/da96127d-2ba5-4772-a2c0-e78ded6d49b6)
