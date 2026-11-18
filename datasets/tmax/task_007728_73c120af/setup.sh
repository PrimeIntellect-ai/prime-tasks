#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/profiling/dumps

    cat << 'EOF' > /home/user/profiling/run_optim.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Error: Missing input file" exit 1
fi
filename=$(basename "$1")
echo "Successfully optimized: $filename"
EOF
    chmod +x /home/user/profiling/run_optim.sh

    cat << 'EOF' > /home/user/profiling/dumps/mat_1.txt
1.0 2.0
3.0 4.0
EOF

    cat << 'EOF' > /home/user/profiling/dumps/mat_2.txt
1.0 2.0
2.0 4.001
EOF

    cat << 'EOF' > /home/user/profiling/dumps/mat_3.txt
5.0 1.0
10.0 2.0
EOF

    cat << 'EOF' > /home/user/profiling/dumps/mat_4.txt
2.0 0.0
0.0 2.0
EOF

    cat << 'EOF' > /home/user/profiling/dumps/mat_5.txt
0.001 0.002
0.002 0.004
EOF

    cat << 'EOF' > /home/user/profiling/dumps/mat_6.txt
10.0 0.0
0.0 0.1
EOF

    chown -R user:user /home/user/profiling
    chmod -R 777 /home/user
