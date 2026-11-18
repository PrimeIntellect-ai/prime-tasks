#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/artifact_summary.wav "For the reproduction pipeline, the projection matrix is a three by three diagonal matrix. The diagonal values are 2.5, -1.5, and 4.2."

    # Create the oracle script
    cat << 'EOF' > /app/oracle_transform.py
import sys

def main():
    if len(sys.argv) != 4:
        sys.exit(1)

    v1 = float(sys.argv[1])
    v2 = float(sys.argv[2])
    v3 = float(sys.argv[3])

    # Diagonal matrix: [2.5, 0, 0], [0, -1.5, 0], [0, 0, 4.2]
    out1 = v1 * 2.5
    out2 = v2 * -1.5
    out3 = v3 * 4.2

    print(f"{out1:.4f} {out2:.4f} {out3:.4f}")

if __name__ == "__main__":
    main()
EOF
    chmod +x /app/oracle_transform.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
