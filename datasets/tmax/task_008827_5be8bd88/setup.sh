#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/logistic_euler.sh
#!/bin/bash
# Usage: ./logistic_euler.sh N0 r
awk -v N0="$1" -v r="$2" 'BEGIN {
    N = N0;
    dt = 2; # BAD STEP SIZE
    for (t=0; t<=10; t+=dt) {
        dN = r * N * (1 - N/1000) * dt;
        N = N + dN;
    }
    printf "%.4f\n", N;
}'
EOF
    chmod +x /home/user/logistic_euler.sh

    cat << 'EOF' > /home/user/strains.txt
Alpha 100 0.5
Beta 50 1.8
Gamma 10 2.5
Delta 200 0.1
EOF

    cat << 'EOF' > /home/user/reference.txt
Alpha 942.8441
Beta 1000.0000
Gamma 1000.0000
Delta 404.6097
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
