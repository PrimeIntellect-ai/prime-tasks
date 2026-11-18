#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make socat cargo
    pip3 install pytest

    mkdir -p /home/user/tool/rust_parser/src

    # Create the broken Rust library
    cat << 'EOF' > /home/user/tool/rust_parser/Cargo.toml
[package]
name = "rust_parser"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib"]
EOF

    cat << 'EOF' > /home/user/tool/rust_parser/src/lib.rs
#[no_mangle]
pub extern "C" fn get_fuzz_payload() -> *const std::ffi::c_char {
    let payload = String::from("FUZZ_PAYLOAD_X99\0");
    payload.as_ptr() as *const std::ffi::c_char
}
EOF

    # Create the C frontend
    cat << 'EOF' > /home/user/tool/main.c
#include <stdio.h>
#include <stdint.h>

extern const char* get_fuzz_payload();

int main() {
    const char* payload = get_fuzz_payload();
    if (payload) {
        printf("Fuzzer sending payload: %s\n", payload);
        return 0;
    }
    return 1;
}
EOF

    # Create the broken Makefile (wrong linking order)
    cat << 'EOF' > /home/user/tool/Makefile
all: http_fuzzer

http_fuzzer: main.o rust_parser/target/debug/librust_parser.a
	gcc -o http_fuzzer rust_parser/target/debug/librust_parser.a main.o -lpthread -ldl

main.o: main.c
	gcc -c main.c

rust_parser/target/debug/librust_parser.a:
	cd rust_parser && cargo build

clean:
	rm -f *.o http_fuzzer
	cd rust_parser && cargo clean
EOF

    # Create the E2E test script
    cat << 'EOF' > /home/user/tool/e2e_test.sh
#!/bin/bash

if [ ! -f "/home/user/tool/http_fuzzer" ]; then
    echo "Error: http_fuzzer not found!"
    exit 1
fi

echo "Starting mock backend..."
echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" > /tmp/resp.txt
python3 -m http.server 8081 --directory /tmp &
BACKEND_PID=$!

sleep 1

echo "Configuring reverse proxy (socat)..."
socat TCP-LISTEN:8080,fork TCP:127.0.0.1:8081 &
PROXY_PID=$!

sleep 1

echo "Running fuzzer against reverse proxy..."
/home/user/tool/http_fuzzer

kill $PROXY_PID
kill $BACKEND_PID
echo "E2E Test Complete. Success!"
EOF
    chmod +x /home/user/tool/e2e_test.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
