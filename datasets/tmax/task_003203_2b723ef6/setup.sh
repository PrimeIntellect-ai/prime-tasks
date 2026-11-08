#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk coreutils
pip3 install pytest

mkdir -p /home/user/pipeline/src

# Setup Phase 1: Journal
cat << 'EOF' > /home/user/pipeline/journal.dat
BEGIN 101
SET config_path /etc/default
SET max_workers 4
COMMIT 101 13
BEGIN 102
SET cache_dir /var/cache
SET timeout 30
BEGIN 103
SET retries 5
COMMIT 103 1
BEGIN 104
SET log_level DEBUG
COMMIT 104 999
BEGIN 105
SET feature_flag true
COMMIT 105 4
EOF

# Setup Phase 2: Delta Debugging
bash -c 'for i in {1..500}; do echo "valid code block $i" > /home/user/pipeline/src/file_$i.src; done'
echo "POISON_SYNTAX_ERROR" > /home/user/pipeline/src/file_314.src

cat << 'EOF' > /home/user/pipeline/compile.sh
#!/bin/bash
if [ "$#" -eq 0 ]; then exit 0; fi
grep -q "POISON_SYNTAX_ERROR" "$@"
if [ $? -eq 0 ]; then
    exit 1
fi
exit 0
EOF
chmod +x /home/user/pipeline/compile.sh

# Setup Phase 3: Numerical Instability
cat << 'EOF' > /home/user/pipeline/metrics.txt
1000000000.01
1000000000.02
1000000000.03
1000000000.01
1000000000.02
EOF

cat << 'EOF' > /home/user/pipeline/aggregate.awk
{
    sum += $1
    sumsq += $1 * $1
}
END {
    mean = sum / NR
    variance = (sumsq / NR) - (mean * mean)
    print "StdDev: " sqrt(variance)
}
EOF

# Setup Build Script
cat << 'EOF' > /home/user/pipeline/build.sh
#!/bin/bash

# Check Phase 1
if [ ! -f /home/user/pipeline/recovered.dat ]; then
    echo "Missing recovered.dat"
    exit 1
fi
EXPECTED_HASH=$(echo -e "SET config_path /etc/default\nSET max_workers 4\nSET retries 5\nSET feature_flag true" | sha256sum | awk '{print $1}')
ACTUAL_HASH=$(sha256sum /home/user/pipeline/recovered.dat | awk '{print $1}')
if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
    echo "recovered.dat is incorrect"
    exit 1
fi

# Check Phase 2
/home/user/pipeline/compile.sh /home/user/pipeline/src/*.src
if [ $? -ne 0 ]; then
    echo "Compilation failed. Poison file still in src/"
    exit 1
fi

# Check Phase 3
AWK_OUT=$(awk -f /home/user/pipeline/aggregate.awk /home/user/pipeline/metrics.txt 2>/dev/null)
if [ $? -ne 0 ] || [[ ! "$AWK_OUT" =~ StdDev:[[:space:]]*0\.007 ]]; then
    echo "Aggregation failed or produced wrong output."
    exit 1
fi

touch /home/user/pipeline/build_success.flag
echo "Build succeeded!"
EOF
chmod +x /home/user/pipeline/build.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
