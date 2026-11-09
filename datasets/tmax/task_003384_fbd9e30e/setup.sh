#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg curl build-essential cargo rustc
pip3 install pytest numpy scipy

mkdir -p /app
cd /app

# Generate /app/voice_sample.wav
python3 -c "
import numpy as np
from scipy.io import wavfile
fs = 16000
t = np.linspace(0, 5, fs * 5, False)
audio = np.sin(2 * np.pi * 440 * t) * 0.5
wavfile.write('/app/voice_sample.wav', fs, audio.astype(np.float32))
"

# Generate /app/projection_matrix.bin
python3 -c "
import numpy as np
matrix = np.random.randn(64, 128).astype(np.float32)
with open('/app/projection_matrix.bin', 'wb') as f:
    f.write(matrix.tobytes())
"

# Create oracle
cat << 'EOF' > oracle.rs
use std::env;
use std::fs::File;
use std::io::{Read, Write, BufReader, BufWriter};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        std::process::exit(1);
    }

    let matrix_bytes = std::fs::read("/app/projection_matrix.bin").unwrap();
    let mut matrix = vec![0.0f32; 8192];
    for i in 0..8192 {
        let bytes = [matrix_bytes[i*4], matrix_bytes[i*4+1], matrix_bytes[i*4+2], matrix_bytes[i*4+3]];
        matrix[i] = f32::from_le_bytes(bytes);
    }

    let mut input = BufReader::new(File::open(&args[1]).unwrap());
    let mut output = BufWriter::new(File::create(&args[2]).unwrap());

    let mut buf = [0u8; 256];
    loop {
        let mut bytes_read = 0;
        while bytes_read < 256 {
            match input.read(&mut buf[bytes_read..]) {
                Ok(0) => break,
                Ok(n) => bytes_read += n,
                Err(_) => break,
            }
        }

        if bytes_read == 0 {
            break;
        }

        let mut vec_in = [0.0f32; 64];
        let floats_read = bytes_read / 4;
        for i in 0..floats_read {
            let b = [buf[i*4], buf[i*4+1], buf[i*4+2], buf[i*4+3]];
            vec_in[i] = f32::from_le_bytes(b);
        }

        let mut vec_out = [0.0f32; 128];
        for i in 0..64 {
            for j in 0..128 {
                vec_out[j] += vec_in[i] * matrix[i * 128 + j];
            }
        }

        let mut sum = 0.0f32;
        for j in 0..128 {
            let val = vec_out[j];
            let relu = if val > 0.0 { val } else { 0.0 };
            sum += relu;
        }
        let mean = sum / 128.0;

        output.write_all(&mean.to_le_bytes()).unwrap();

        if bytes_read < 256 {
            break;
        }
    }
}
EOF

rustc -O oracle.rs -o /app/oracle_extractor
rm oracle.rs

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
