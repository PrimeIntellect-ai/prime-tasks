#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc strace
    pip3 install pytest

    mkdir -p /home/user/malware_analysis
    mkdir -p /home/user/bad_binaries

    # Dummy date command that causes an issue
    cat << 'EOF' > /home/user/bad_binaries/date
#!/bin/bash
sleep 10
exit 1
EOF
    chmod +x /home/user/bad_binaries/date

    # Log file with inconsistent formats
    cat << 'EOF' > /home/user/malware_analysis/beacons.log
[BEACON] 2023-10-12 10:00:00.100
[BEACON] 2023-10-12 10:00:01.600
[BEACON] 2023-10-12T10:00:03.200Z
[BEACON] 2023-10-12 10:00:05.900
[BEACON] 2023-10-12T10:00:10.150Z
EOF

    # Buggy script
    cat << 'EOF' > /home/user/malware_analysis/process_logs.sh
#!/bin/bash

export PATH=/home/user/bad_binaries:$PATH

mapfile -t lines < /home/user/malware_analysis/beacons.log
> /home/user/malware_analysis/intervals.txt

prev_time=""
i=0
total_diff="0"

while [ $i -lt ${#lines[@]} ]; do
    line="${lines[$i]}"

    # Extract timestamp (Bug: regex doesn't correctly handle T and Z in ISO format)
    if [[ $line =~ \[BEACON\]\ ([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+) ]]; then
        ts="${BASH_REMATCH[1]}"

        # Convert to epoch seconds with nanoseconds
        epoch=$(date -d "$ts" +%s.%N)

        if [ -n "$prev_time" ]; then
            # Calculate difference (Bug: bc missing -l for float precision, causing truncation)
            diff=$(echo "$epoch - $prev_time" | bc)
            echo "$diff" >> /home/user/malware_analysis/intervals.txt
            total_diff=$(echo "$total_diff + $diff" | bc)
        fi
        prev_time=$epoch
        ((i++))
    else
        # Bug: Infinite loop if regex fails (doesn't increment i)
        # To fix, they must increment i or fix regex so it parses all lines
        # But even if regex is fixed, safe practice is to increment i here or use a for loop.
        echo "Failed to parse line: $line" >&2
        # Missing ((i++))
    fi
done

echo "$total_diff" > /home/user/malware_analysis/total_time.log
EOF
    chmod +x /home/user/malware_analysis/process_logs.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
