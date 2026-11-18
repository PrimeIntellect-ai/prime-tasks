#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest

    mkdir -p /app/verifier/clean /app/verifier/evil /app/data

    # Generate clean files
    cat << 'EOF' > /app/verifier/clean/clean1.txt
Total_Score: 10.500
Alignment 1: Primer=ATCGATCGATCGATC Target=ATCGATCGATCGATC Score=5.250
Alignment 2: Primer=GCTAGCTAGCTAGCTA Target=GCTAGCTAGCTAGCTA Score=5.250
EOF

    cat << 'EOF' > /app/verifier/clean/clean2.txt
Total_Score: 0.123
Alignment 1: Primer=ATCGATCGATCGATCGATCG Target=ATCGATCGATCGATCGATCG Score=0.123
EOF

    # Generate evil files
    cat << 'EOF' > /app/verifier/evil/evil1_sum_error.txt
Total_Score: 10.000
Alignment 1: Primer=ATCGATCGATCGATC Target=ATCGATCGATCGATC Score=5.000
Alignment 2: Primer=GCTAGCTAGCTAGCTA Target=GCTAGCTAGCTAGCTA Score=4.990
EOF

    cat << 'EOF' > /app/verifier/evil/evil2_nan.txt
Total_Score: NaN
Alignment 1: Primer=ATCGATCGATCGATC Target=ATCGATCGATCGATC Score=5.000
EOF

    cat << 'EOF' > /app/verifier/evil/evil3_primer_short.txt
Total_Score: 5.000
Alignment 1: Primer=ATCG Target=ATCGATCGATCGATC Score=5.000
EOF

    cat << 'EOF' > /app/verifier/evil/evil4_primer_long.txt
Total_Score: 5.000
Alignment 1: Primer=ATCGATCGATCGATCGATCGATCGATCGATCG Target=ATCGATCGATCGATC Score=5.000
EOF

    # Generate Video Fixture
    ffmpeg -f lavfi -i color=c=blue:s=320x240:d=16 -f lavfi -i color=c=black:s=320x240:d=14 -filter_complex "[0:v][1:v]concat=n=2:v=1:a=0[v]" -map "[v]" -c:v libx264 -pix_fmt yuv420p /app/data/convergence_sim.mp4 -y

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
