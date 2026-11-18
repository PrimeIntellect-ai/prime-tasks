#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install task-specific dependencies
    apt-get install -y gcc rustc sqlite3 libsqlite3-dev

    # Create directories
    mkdir -p /home/user/pipeline/src
    cd /home/user/pipeline

    # 1. Create initial SQLite database
    sqlite3 db.sqlite "CREATE TABLE sessions (username TEXT, token TEXT);"
    sqlite3 db.sqlite "INSERT INTO sessions (username, token) VALUES ('admin', 'secret123');"

    # 2. Create the broken C shared library code
    cat << 'EOF' > src/auth.c
#include <stdio.h>

// Outdated ABI: missing expiry
int check_auth(const char* username, const char* token) {
    // Legacy logic
    return 1;
}
EOF

    # 3. Create the broken Rust code (Borrow Checker error)
    cat << 'EOF' > src/main.rs
use std::ffi::CString;
use std::os::raw::c_char;

extern "C" {
    fn check_auth(username: *const c_char, token: *const c_char, expiry: i32) -> i32;
}

fn main() {
    let user = "admin";
    let token = "secret123";

    // BUG: CString::new creates a temporary that is dropped immediately, 
    // leaving dangling pointers.
    let u_ptr = CString::new(user).unwrap().as_ptr();
    let t_ptr = CString::new(token).unwrap().as_ptr();

    let result = unsafe {
        check_auth(u_ptr, t_ptr, 3600)
    };

    println!("Auth Check: {}", result);
}
EOF

    # 4. Create the build script
    cat << 'EOF' > build.sh
#!/bin/bash

# Build the C shared library
gcc -shared -fPIC -o libauth.so src/auth.c
# Build the Rust application
rustc src/main.rs -L . -l auth
# Run it
LD_LIBRARY_PATH=. ./main > success.log
EOF
    chmod +x build.sh

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
