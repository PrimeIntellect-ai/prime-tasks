#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make valgrind cargo rustc
    pip3 install pytest

    mkdir -p /home/user/pr_review/rust_interner/src

    # Create the Makefile
    cat << 'EOF' > /home/user/pr_review/Makefile
test_runner: test.c rust_interner/target/debug/librust_interner.a
	gcc -g -O0 test.c -L./rust_interner/target/debug -lrust_interner -lpthread -ldl -lm -o test_runner

rust_interner/target/debug/librust_interner.a:
	cd rust_interner && cargo build

clean:
	rm -f test_runner
	cd rust_interner && cargo clean
EOF

    # Create the C test file
    cat << 'EOF' > /home/user/pr_review/test.c
#include <stdio.h>
#include <assert.h>

// Opaque pointer to the Rust struct
typedef struct Interner Interner;

extern Interner* interner_new();
extern size_t interner_add(Interner* interner, const char* s);
extern void interner_free(Interner* interner);

int main() {
    Interner* interner = interner_new();

    size_t id1 = interner_add(interner, "hello");
    size_t id2 = interner_add(interner, "world");
    size_t id3 = interner_add(interner, "hello");

    assert(id1 == 0);
    assert(id2 == 1);
    assert(id3 == 0); // "hello" should be interned to the same ID

    interner_free(interner);
    printf("Tests passed.\n");
    return 0;
}
EOF

    # Create the Cargo.toml (Intentionally missing the staticlib type, without using the word in comments)
    cat << 'EOF' > /home/user/pr_review/rust_interner/Cargo.toml
[package]
name = "rust_interner"
version = "0.1.0"
edition = "2021"

[lib]
# PR Author forgot to specify the correct output kind
EOF

    # Create the broken Rust code
    cat << 'EOF' > /home/user/pr_review/rust_interner/src/lib.rs
use std::collections::HashMap;
use std::os::raw::c_char;
use std::ffi::CStr;

pub struct Interner {
    map: HashMap<String, usize>,
    counter: usize,
}

impl Interner {
    fn new() -> Self {
        Interner {
            map: HashMap::new(),
            counter: 0,
        }
    }

    fn intern(&mut self, s: &str) -> usize {
        if let Some(&id) = self.map.get(s) {
            return id;
        }
        let id = self.counter;
        self.counter += 1;
        // BUG 1: Borrow checker / Type error: map expects String, but s is &str
        self.map.insert(s, id);
        id
    }
}

#[no_mangle]
pub extern "C" fn interner_new() -> *mut Interner {
    Box::into_raw(Box::new(Interner::new()))
}

#[no_mangle]
pub extern "C" fn interner_add(ptr: *mut Interner, s: *const c_char) -> usize {
    if ptr.is_null() || s.is_null() {
        return 0;
    }
    let interner = unsafe { &mut *ptr };
    let c_str = unsafe { CStr::from_ptr(s) };
    let str_slice = c_str.to_str().unwrap_or("");
    interner.intern(str_slice)
}

#[no_mangle]
pub extern "C" fn interner_free(ptr: *mut Interner) {
    if ptr.is_null() {
        return;
    }
    // BUG 2: Memory leak: drop_in_place drops the fields but leaks the Box allocation itself.
    // The correct way is: unsafe { let _ = Box::from_raw(ptr); }
    unsafe { std::ptr::drop_in_place(ptr); }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/pr_review
    chmod -R 777 /home/user
