#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip cargo rustc patch gawk
pip3 install pytest

useradd -m -s /bin/bash user || true

# Create directories
mkdir -p /home/user/rust_processor/src
mkdir -p /home/user/patches

# Create Rust project files
cat << 'EOF' > /home/user/rust_processor/Cargo.toml
[package]
name = "rust_processor"
version = "0.1.0"
edition = "2021"

[dependencies]
ureq = { version = "2.6", features = ["json"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

cat << 'EOF' > /home/user/rust_processor/src/main.rs
use serde::Deserialize;

#[derive(Deserialize)]
struct Response {
    status: String,
    // BUG: Missing payload field
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resp: Response = ureq::get("http://127.0.0.1:8080/data")
        .call()?
        .into_json()?;

    // BUG: Syntax error, missing semicolon
    println!("Status: {}", resp.status)
    // println!("Payload: {}", resp.payload);

    Ok(())
}
EOF

# Create patches
cat << 'EOF' > /home/user/patches/versions.json
{
  "versions": ["1.0.5", "1.1.0", "1.2.4", "1.3.1", "2.0.1", "2.1.0"]
}
EOF

# Valid patch for 1.3.1
cat << 'EOF' > /home/user/patches/fix_1.3.1.patch
--- a/src/main.rs
+++ b/src/main.rs
@@ -4,14 +4,14 @@
 #[derive(Deserialize)]
 struct Response {
     status: String,
-    // BUG: Missing payload field
+    payload: i32,
 }

 fn main() -> Result<(), Box<dyn std::error::Error>> {
     let resp: Response = ureq::get("http://127.0.0.1:8080/data")
         .call()?
         .into_json()?;

-    // BUG: Syntax error, missing semicolon
-    println!("Status: {}", resp.status)
-    // println!("Payload: {}", resp.payload);
+    println!("Status: {}", resp.status);
+    println!("Payload: {}", resp.payload);

     Ok(())
 }
EOF

# Dummy patch for 1.2.4
echo "dummy diff" > /home/user/patches/fix_1.2.4.patch

# Calculate hashes
HASH_131=$(sha256sum /home/user/patches/fix_1.3.1.patch | awk '{print $1}')
HASH_124=$(sha256sum /home/user/patches/fix_1.2.4.patch | awk '{print $1}')

cat << EOF > /home/user/patches/checksums.txt
1.3.1 $HASH_131
1.2.4 $HASH_124
EOF

chown -R user:user /home/user/rust_processor /home/user/patches
chmod -R 777 /home/user
