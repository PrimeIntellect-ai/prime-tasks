#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/ws_server
    mkdir -p /home/user/patch_client/src
    mkdir -p /home/user/project_files

    # Create config.json
    cat << 'EOF' > /home/user/project_files/config.json
{
  "version": "1.0",
  "name": "legacy_project",
  "files": [
    "old_file.txt"
  ]
}
EOF

    # Create patch.diff
    cat << 'EOF' > /home/user/ws_server/patch.diff
--- config.json
+++ config.json
@@ -2,5 +2,6 @@
   "version": "1.0",
-  "name": "legacy_project",
+  "name": "organized_project",
   "files": [
-    "old_file.txt"
+    "new_file1.txt",
+    "new_file2.txt"
   ]
 }
EOF

    # Create Go Server
    cat << 'EOF' > /home/user/ws_server/main.go
package main

import (
	"io/ioutil"
	"log"
	"net/http"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{}

func handler(w http.ResponseWriter, r *http.Request) {
	conn, _ := upgrader.Upgrade(w, r, nil)
	defer conn.Close()

	patchData, _ := ioutil.ReadFile("patch.diff")
	ch := make(chan string)

	ch <- string(patchData) // DEADLOCK

	go func() {
		conn.WriteMessage(websocket.TextMessage, []byte(<-ch))
	}()
}

func main() {
	http.HandleFunc("/", handler)
	log.Fatal(http.ListenAndServe("127.0.0.1:8080", nil))
}
EOF

    cd /home/user/ws_server
    go mod init ws_server
    go get github.com/gorilla/websocket

    # Create Rust Client Cargo.toml
    cat << 'EOF' > /home/user/patch_client/Cargo.toml
[package]
name = "patch_client"
version = "0.1.0"
edition = "2021"

[dependencies]
diffy = "0.3"
tungstenite = "0.20"
url = "2.4"

[dev-dependencies]
proptest = "1.0"
EOF

    # Create Rust Client patcher.rs
    cat << 'EOF' > /home/user/patch_client/src/patcher.rs
use diffy::Patch;

pub fn apply_diff(original: &str, patch_str: &str) -> String {
    // FIX ME
    original.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;
    use diffy::create_patch;

    proptest! {
        #[test]
        fn test_patch_application(orig in "[a-z]{5,10}\n[a-z]{5,10}", modified in "[a-z]{5,10}\n[a-z]{5,10}") {
            let patch = create_patch(&orig, &modified);
            let patch_str = patch.to_string();
            let result = apply_diff(&orig, &patch_str);
            prop_assert_eq!(result, modified);
        }
    }
}
EOF

    # Create Rust Client main.rs
    cat << 'EOF' > /home/user/patch_client/src/main.rs
mod patcher;

use std::fs;
use tungstenite::{connect, Message};
use url::Url;

fn main() {
    let (mut socket, _) = connect(Url::parse("ws://127.0.0.1:8080/").unwrap()).expect("Can't connect");
    let msg = socket.read_message().expect("Error reading message");
    let patch_str = msg.into_text().unwrap();
    let config_path = "/home/user/project_files/config.json";
    let original = fs::read_to_string(config_path).expect("Unable to read config.json");
    let patched = patcher::apply_diff(&original, &patch_str);
    fs::write("/home/user/project_files/config_fixed.json", patched).expect("Unable to write config_fixed.json");
}
EOF

    cd /home/user/patch_client
    # Fetch dependencies to cache them
    cargo fetch || true

    chmod -R 777 /home/user
