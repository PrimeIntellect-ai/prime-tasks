#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make cargo patch curl
    pip3 install pytest websockets

    # Create directories
    mkdir -p /home/user/hybrid_project/c_lib
    mkdir -p /home/user/hybrid_project/rust_server/src

    # Create the C source file
    cat << 'EOF' > /home/user/hybrid_project/c_lib/transform.c
#include <string.h>

void transform_string(const char* input, char* output) {
    int len = strlen(input);
    for (int i = 0; i < len; i++) {
        output[i] = input[len - 1 - i];
    }
    output[len] = '\0';
    strcat(output, "_processed");
}
EOF

    # Create the broken Makefile
    cat << 'EOF' > /home/user/hybrid_project/c_lib/Makefile
all: libtransform.so

libtransform.so: transform.c
	gcc -o libtransform.so transform.c

clean:
	rm -f *.so
EOF

    # Create the patch file
    cat << 'EOF' > /home/user/hybrid_project/c_lib/fix_makefile.patch
--- Makefile
+++ Makefile
@@ -2,5 +2,5 @@

 libtransform.so: transform.c
-	gcc -o libtransform.so transform.c
+	gcc -shared -fPIC -o libtransform.so transform.c

 clean:
EOF

    # Create the Rust WebSocket Server Cargo.toml
    cat << 'EOF' > /home/user/hybrid_project/rust_server/Cargo.toml
[package]
name = "rust_server"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1.28", features = ["full"] }
tokio-tungstenite = "0.19"
futures-util = "0.3"
libc = "0.2"
EOF

    # Create the Rust main.rs
    cat << 'EOF' > /home/user/hybrid_project/rust_server/src/main.rs
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;
use futures_util::{StreamExt, SinkExt};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

extern "C" {
    fn transform_string(input: *const c_char, output: *mut c_char);
}

#[tokio::main]
async fn main() {
    let listener = TcpListener::bind("127.0.0.1:9001").await.unwrap();
    println!("Listening on: 127.0.0.1:9001");

    while let Ok((stream, _)) = listener.accept().await {
        tokio::spawn(async move {
            let mut ws_stream = accept_async(stream).await.expect("Error during the websocket handshake occurred");
            if let Some(msg) = ws_stream.next().await {
                let msg = msg.unwrap();
                if msg.is_text() {
                    let text = msg.to_text().unwrap();
                    let c_input = CString::new(text).unwrap();
                    let mut c_output = vec![0u8; 1024];

                    unsafe {
                        transform_string(c_input.as_ptr(), c_output.as_mut_ptr() as *mut c_char);
                    }

                    let c_res = unsafe { CStr::from_ptr(c_output.as_ptr() as *const c_char) };
                    let response = c_res.to_str().unwrap().to_string();

                    ws_stream.send(tokio_tungstenite::tungstenite::Message::Text(response)).await.unwrap();
                }
            }
        });
    }
}
EOF

    # Create build.rs
    cat << 'EOF' > /home/user/hybrid_project/rust_server/build.rs
fn main() {
    println!("cargo:rustc-link-search=native=/home/user/hybrid_project/c_lib");
    println!("cargo:rustc-link-lib=dylib=transform");
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/hybrid_project
    chmod -R 777 /home/user
