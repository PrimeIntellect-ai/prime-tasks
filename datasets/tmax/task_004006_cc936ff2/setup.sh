#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/raw_math_data

    # Create doc1.txt in UTF-8
    cat << 'EOF' > /home/user/raw_math_data/doc1.txt
Experiment Alpha. Date: 2023-01-01.
Results show that M1 = [[2, 0], [1, 5]].
The growth rate follows P(x) = 2x^2 + 3x - 1.
EOF

    # Create doc2.dat in UTF-16LE
    cat << 'EOF' > /tmp/doc2.txt
Beta trial.
Observed matrix [[-1, 4], [0, 3]].
Decay is x^2 - x.
EOF
    iconv -f UTF-8 -t UTF-16LE /tmp/doc2.txt > /home/user/raw_math_data/doc2.dat

    # Create doc3.log in ISO-8859-1
    cat << 'EOF' > /tmp/doc3.txt
Gamma log. Error ±0.05.
matrix=[[10, 2], [3, 1]]
Equation: 5x - 7.
EOF
    iconv -f UTF-8 -t ISO-8859-1 /tmp/doc3.txt > /home/user/raw_math_data/doc3.log

    # Clean up temp files
    rm /tmp/doc2.txt /tmp/doc3.txt

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
