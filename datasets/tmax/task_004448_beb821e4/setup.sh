#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git rustc cargo gdb
    pip3 install pytest

    # Generate a dummy WAV file
    mkdir -p /app
    python3 -c "
import wave, struct
with wave.open('/app/suspicious_audio.wav', 'w') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(44100)
    for i in range(44100):
        w.writeframesraw(struct.pack('<h', 0))
"

    # Create the git repo
    mkdir -p /home/user/investigator_repo
    cd /home/user/investigator_repo
    git init
    git config user.email "attacker@example.com"
    git config user.name "Attacker"

    cargo init --bin
    cat << 'EOF' > src/main.rs
fn extract_payload(samples: &[i16]) -> String {
    let mut extracted = Vec::new();
    let len = samples.len() as i32;
    for i in 0..25 {
        // Bug: signed integer overflow
        let idx: i32 = (i as i32 * 100_000) % len;
        extracted.push((samples[idx as usize] & 0xFF) as u8);
    }
    String::from_utf8_lossy(&extracted).into_owned()
}

fn main() {
    println!("Run extraction...");
}
EOF
    git add .
    git commit -m "Initial commit of extraction tool"

    # Delete the code to simulate cleanup
    git rm -r src
    git commit -m "Cleanup traces"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
