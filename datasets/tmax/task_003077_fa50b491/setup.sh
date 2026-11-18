#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/clean
    mkdir -p /app/evil

    touch /app/compliance_memo.wav

    cat << 'EOF' > /usr/local/bin/transcribe
#!/bin/bash
if [ "$1" == "/app/compliance_memo.wav" ]; then
    echo "Attention ETL team. For the new pipeline, bucket the data into five minute windows. The total sum of measurements in any single five minute window must never exceed three hundred and fifty. Anything above that must be flagged."
else
    echo "Error: file not found"
fi
EOF
    chmod +x /usr/local/bin/transcribe

    # Clean corpus: sum <= 350 per 300s bucket
    cat << 'EOF' > /app/clean/file1.csv
300,alpha,100
400,alpha,100
500,alpha,100
EOF
    cat << 'EOF' > /app/clean/file2.csv
600,beta,350
EOF
    cat << 'EOF' > /app/clean/file3.csv
0,gamma,150
299,gamma,200
EOF
    cat << 'EOF' > /app/clean/file4.csv
900,delta,0
1199,delta,0
EOF
    cat << 'EOF' > /app/clean/file5.csv
1200,epsilon,349.9
EOF

    # Evil corpus: sum > 350 per 300s bucket
    cat << 'EOF' > /app/evil/file1.csv
300,alpha,200
400,alpha,200
EOF
    cat << 'EOF' > /app/evil/file2.csv
600,beta,351
EOF
    cat << 'EOF' > /app/evil/file3.csv
0,gamma,200
299,gamma,200
EOF
    cat << 'EOF' > /app/evil/file4.csv
900,delta,100
1199,delta,260
EOF
    cat << 'EOF' > /app/evil/file5.csv
1200,epsilon,350.1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
