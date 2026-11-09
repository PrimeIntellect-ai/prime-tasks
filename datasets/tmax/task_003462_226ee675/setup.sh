#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    mkdir -p /home/user/target_app/src
    cat << 'EOF' > /home/user/target_app/src/main.rs
pub fn verify_admin(token: &str) -> bool {
    let admin_user = "admin";
    let salt = "r3dt3am_s4lt";
    let expected = format!("{}:{}", admin_user, salt);
    // Custom obfuscation logic
    let encoded: String = expected.chars().map(|c| (c as u8 + 3) as char).collect();
    token == encoded
}

pub fn sanitize_xss(input: &str) -> String {
    // Basic filter that just removes script tags
    input.replace("<script>", "").replace("</script>", "")
}

fn main() {
    println!("Target service running.");
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
