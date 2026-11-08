#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    bash -c '
    user_home="/home/user"
    mkdir -p "$user_home/perf_tools"
    cd "$user_home"

    # 1. Create the simulated memory dump
    dd if=/dev/urandom of=app_memory.dump bs=1K count=10 2>/dev/null
    echo "PERF_RECORD: 1699999999 45.5" >> app_memory.dump
    dd if=/dev/urandom bs=1K count=2 >> app_memory.dump 2>/dev/null
    echo "PERF_RECORD: 1700000050 10.2" >> app_memory.dump
    echo "PERF_RECORD: 1700000060 15.5" >> app_memory.dump
    dd if=/dev/urandom bs=1K count=2 >> app_memory.dump 2>/dev/null
    echo "PERF_RECORD: 1700000070 20.1" >> app_memory.dump
    echo "PERF_RECORD: 1700000080 30.0" >> app_memory.dump

    # 2. Setup Git Repository
    cd "$user_home/perf_tools"
    git init
    git config user.name "Test User"
    git config user.email "test@example.com"

    # Good script (v1.0)
    cat << "EOF" > analyze_profile.sh
#!/bin/bash
INPUT=$1
START=$2
COUNT=0
TOTAL=0
while read -r ts val; do
    if [ "$ts" -ge "$START" ]; then
        COUNT=$((COUNT + 1))
        TOTAL=$(echo "$TOTAL + $val" | bc -l)
    fi
done < "$INPUT"

if [ "$COUNT" -gt 0 ]; then
    AVG=$(echo "scale=3; $TOTAL / $COUNT" | bc -l)
    printf "Processed: %d records\nAverage Latency: %.3f ms\n" "$COUNT" "$AVG"
fi
EOF
    chmod +x analyze_profile.sh
    git add analyze_profile.sh
    git commit -m "Initial commit - working aggregation"
    git tag v1.0

    # Add 4 dummy commits
    for i in {1..4}; do
        echo "# dummy comment $i" >> analyze_profile.sh
        git commit -am "Dummy commit $i"
    done

    # The BAD commit (introduces all 3 bugs)
    cat << "EOF" > analyze_profile.sh
#!/bin/bash
INPUT=$1
START=$2
COUNT=0
TOTAL=0

# BUG 2: Boundary - tail -n +1 drops nothing, but wait, let us read up to N-1 lines
# Actually, let us just drop the last line using head -n -1
tmpfile=$(mktemp)
head -n -1 "$INPUT" > "$tmpfile"

while read -r ts val; do
    # BUG 3: Timezone offset error
    if [ "$ts" -ge $((START - 3600)) ]; then
        COUNT=$((COUNT + 1))
        # BUG 1: FP truncation using bash arithmetic (removes decimal)
        int_val=${val%.*}
        TOTAL=$((TOTAL + int_val))
    fi
done < "$tmpfile"
rm -f "$tmpfile"

if [ "$COUNT" -gt 0 ]; then
    AVG=$(echo "scale=3; $TOTAL / $COUNT" | bc -l)
    printf "Processed: %d records\nAverage Latency: %.3f ms\n" "$COUNT" "$AVG"
fi
EOF
    git commit -am "Optimize script performance and add TZ offset"
    BAD_COMMIT=$(git rev-parse HEAD)

    # Save the bad commit to a hidden file for truth verification
    echo "$BAD_COMMIT" > "$user_home/.truth_bad_commit"

    # Add 4 more dummy commits
    for i in {5..8}; do
        echo "# dummy comment $i" >> analyze_profile.sh
        git commit -am "Dummy commit $i"
    done
    '

    chmod -R 777 /home/user
