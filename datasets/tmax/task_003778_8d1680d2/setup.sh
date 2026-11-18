#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential git ffmpeg cargo rustc
    pip3 install pytest

    # Create directories
    mkdir -p /app /opt/oracle /home/user/releases /home/user/workspace

    # Generate the audio fixture
    ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" -c:a pcm_s16le /app/voice_record.wav

    # Create the oracle
    cat << 'EOF' > /opt/oracle/main.rs
use std::io::{self, Read, Write};
fn main() {
    let mut buffer = Vec::new();
    io::stdin().read_to_end(&mut buffer).unwrap();
    for byte in buffer.iter_mut() {
        *byte = byte.rotate_right(3) ^ 0x8C;
    }
    io::stdout().write_all(&buffer).unwrap();
}
EOF
    rustc -O /opt/oracle/main.rs -o /opt/oracle/audio_service_oracle
    chmod +x /opt/oracle/audio_service_oracle

    # Create user
    useradd -m -s /bin/bash user || true

    # Set permissions
    chown -R user:user /home/user/releases
    chown user:user /app/voice_record.wav
    chmod -R 777 /home/user
