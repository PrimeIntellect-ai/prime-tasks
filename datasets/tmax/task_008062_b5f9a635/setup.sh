#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/legacy_analytics
    cd /home/user/legacy_analytics

    cat << 'EOF' > process_logs.sh
#!/bin/bash

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <file.csv> <month>"
    exit 1
fi

FILE=$1
TARGET_MONTH=$2

declare -A totals

# Bug 1: tail -n +3 skips the first valid data row (off-by-one)
# Bug 2: while read drops the last line if it lacks a trailing newline
# Bug 3: $((month)) treats "08" and "09" as invalid octal numbers
while IFS=, read -r date user bytes; do
    month=$(echo "$date" | cut -d'-' -f2)

    if [ $((month)) -eq $TARGET_MONTH ]; then
        totals["$user"]=$(( totals["$user"] + bytes ))
    fi
done < <(tail -n +3 "$FILE")

for user in "${!totals[@]}"; do
    echo "$user: ${totals[$user]}"
done | sort
EOF
    chmod +x process_logs.sh

    cat << 'EOF' > access_logs.csv
date,user_id,bytes
2023-08-01,user_1,1000
2023-07-15,user_2,500
2023-08-05,user_2,2000
2023-09-10,user_1,3000
2023-08-20,user_1,1500
EOF
    echo -n "2023-08-31,user_3,800" >> access_logs.csv

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
