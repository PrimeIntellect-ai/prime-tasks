#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc rustc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/data

# Create the dummy compiled binary
cat << 'EOF' > /tmp/legacy_key_service.c
char* k = "OLD_KEY_11223344";
int main() { return 0; }
EOF
gcc -o /home/user/legacy_key_service /tmp/legacy_key_service.c
rm /tmp/legacy_key_service.c

# Create the encrypted credentials file
python3 -c '
import base64
pt = "admin:super_secret_password_123\ndb_user:db_pass_4567\n"
key = "OLD_KEY_11223344"
encrypted = bytearray()
for i in range(len(pt)):
    encrypted.append(ord(pt[i]) ^ ord(key[i % len(key)]))
with open("/home/user/data/creds.enc", "wb") as f:
    f.write(base64.b64encode(encrypted))
'

# Create the vulnerable Rust server code
cat << 'EOF' > /home/user/cred_server.rs
use std::process::Command;
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 { return; }
    let user = &args[1];
    // VULNERABLE
    let output = Command::new("sh")
        .arg("-c")
        .arg(format!("cat /home/user/data/creds_v2.enc | grep {}", user))
        .output()
        .expect("failed to execute process");
    println!("{}", String::from_utf8_lossy(&output.stdout));
}
EOF

chmod -R 777 /home/user
