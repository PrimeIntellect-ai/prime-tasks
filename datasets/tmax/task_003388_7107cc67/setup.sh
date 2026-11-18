#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git bc
    pip3 install pytest

    # 1. Git Forensics
    mkdir -p /home/user/pipeline-config
    cd /home/user/pipeline-config
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"
    echo "PRECISION_SCALE=20" > math_thresholds.env
    echo "MAX_LATENCY_THRESHOLD=999.999" >> math_thresholds.env
    git add math_thresholds.env
    git commit -m "Add math thresholds"
    rm math_thresholds.env
    git add -u
    git commit -m "Remove math thresholds accidentally"

    # 2. Vendored Package
    mkdir -p /app/vendored/parallel-log-calc-1.0.4/bin
    cat << 'EOF' > /app/vendored/parallel-log-calc-1.0.4/bin/aggregate.sh
#!/bin/bash
DIR=$1
for file in $(ls $DIR); do
    cat "$DIR/$file" >> /tmp/math_buffer
done
awk '{sum+=$1} END {print sum}' /tmp/math_buffer
EOF
    chmod +x /app/vendored/parallel-log-calc-1.0.4/bin/aggregate.sh

    # 3. Test Logs
    mkdir -p /home/user/test_logs
    echo "123.4567890123" > "/home/user/test_logs/log node 1.txt"
    echo "987.6543210987" > "/home/user/test_logs/log node 2.txt"

    # 4. Clean Corpus
    mkdir -p /home/user/corpora/clean
    for i in $(seq 1 10); do
        echo "2023-10-01T12:00:00Z 12.345678" > "/home/user/corpora/clean/log_$i.txt"
    done

    # 5. Evil Corpus
    mkdir -p /home/user/corpora/evil
    echo "2023-10-01T12:00:00Z NaN" > "/home/user/corpora/evil/bad1.txt"
    echo "2023-10-01T12:00:00Z -Infinity" > "/home/user/corpora/evil/bad2.txt"
    echo "2023-10-01T12:00:00Z 1.000000000000000000000001" > "/home/user/corpora/evil/bad3.txt"
    echo "2023-10-01T12:00:00Z 12.345678" > "/home/user/corpora/evil/evil_name_$(echo -e '\n').txt"
    echo "2023-10-01T12:00:00Z 12.345678" > "/home/user/corpora/evil/\$(touch pwned).txt"
    for i in $(seq 6 10); do
        echo "2023-10-01T12:00:00Z NaN" > "/home/user/corpora/evil/bad$i.txt"
    done

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
    chmod -R 777 /app
