#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/data/ref_serial
    mkdir -p /home/user/data/run_parallel

    # svd_matrix.txt
    cat << 'EOF' > /home/user/data/ref_serial/svd_matrix.txt
1.123 2.345 3.456
4.567 5.678 6.789
7.890 8.901 9.012
EOF

    cat << 'EOF' > /home/user/data/run_parallel/svd_matrix.txt
1.123 2.345 3.456
4.567 5.663 6.789
7.890 8.901 9.012
EOF

    # lu_matrix.txt
    cat << 'EOF' > /home/user/data/ref_serial/lu_matrix.txt
0.500 0.600
0.700 0.800
EOF

    cat << 'EOF' > /home/user/data/run_parallel/lu_matrix.txt
0.500 0.602
0.700 0.800
EOF

    # qr_matrix.txt
    cat << 'EOF' > /home/user/data/ref_serial/qr_matrix.txt
9.999 8.888 7.777
6.666 5.555 4.444
EOF

    cat << 'EOF' > /home/user/data/run_parallel/qr_matrix.txt
9.999 8.888 7.777
6.621 5.555 4.444
EOF

    # cholesky_matrix.txt
    cat << 'EOF' > /home/user/data/ref_serial/cholesky_matrix.txt
1.0 0.0 0.0
2.0 3.0 0.0
4.0 5.0 6.0
EOF

    cat << 'EOF' > /home/user/data/run_parallel/cholesky_matrix.txt
1.0 0.0 0.0
2.0 3.0 0.0
4.0 5.0 6.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/data
    chmod -R 777 /home/user
