#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip bc sed grep coreutils
pip3 install pytest

mkdir -p /home/user

# Create the query results log with edge cases (carriage returns and appended text)
cat << 'EOF' > /home/user/query_results.log
[INFO] Query returned: val=10.0
[INFO] Query returned: val=20.0
[INFO] Query returned: val=15.0, status=OK
[WARN] Query timeout
[INFO] Query returned: val=12.0
[INFO] Query returned: val=18.5 
EOF

# Append a hidden \r to the 12.0 line to simulate CRLF issues
sed -i 's/val=12.0/val=12.0\r/' /home/user/query_results.log

# Create the buggy script
cat << 'EOF' > /home/user/analyze_metrics.sh
#!/bin/bash
data_file="/home/user/query_results.log"
estimate=10.000
delta=1.000
threshold=0.010

# Convergence loop
while [ "$(echo "$delta > $threshold" | bc -l)" -eq 1 ]; do
    sum=0
    count=0
    while read -r line; do
        if echo "$line" | grep -q "val="; then
            # BUG 1: format parsing edge-case. Doesn't strip appended text or \r
            val=$(echo "$line" | sed -n 's/.*val=\([^ ]*\).*/\1/p')

            # BUG 2: If bc fails due to bad input (e.g. "15.0," or "12.0\r"), diff is empty
            diff=$(echo "scale=3; ($val - $estimate) / 2" | bc -l 2>/dev/null)

            if [ -n "$diff" ]; then
                sum=$(echo "scale=3; $sum + $diff" | bc -l)
                count=$((count + 1))
            fi
        fi
    done < "$data_file"

    if [ "$count" -eq 0 ]; then
        echo "Error: No valid data points found."
        exit 1
    fi

    avg_diff=$(echo "scale=3; $sum / $count" | bc -l)
    new_estimate=$(echo "scale=3; $estimate + $avg_diff" | bc -l)

    # Calculate absolute delta
    delta=$(echo "scale=3; $new_estimate - $estimate" | bc -l)
    if [ "$(echo "$delta < 0" | bc -l)" -eq 1 ]; then
        delta=$(echo "scale=3; $delta * -1" | bc -l)
    fi

    # BUG 3 (Convergence failure): If count is skewed or avg_diff is exactly 0 due to bc parsing failures on the actual valid diffs, delta becomes 0, but if it fails entirely it might stall. Actually, if avg_diff is 0, delta is 0, loop exits. 
    # If delta calculation fails, delta might be empty, and loop breaks.
    # To cause an infinite loop: if 'val' has a comma, bc syntax error -> diff is empty -> count doesn't increment for that row.
    # If ALL rows fail, count=0 -> exits. 
    # If SOME rows fail, it converges to the WRONG average. 
    # Wait, the prompt states it hangs indefinitely. 
    # If delta evaluates to exactly the threshold or gets stuck bouncing: 
    # Let's make sure the script actually infinite loops. If `new_estimate` equals `estimate`, `delta` is 0. Loop ends.
    # What if avg_diff calculation fails?

    estimate=$new_estimate
done

echo "$estimate" > /home/user/final_metric.txt
EOF

chmod +x /home/user/analyze_metrics.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
