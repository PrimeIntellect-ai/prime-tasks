#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages
    apt-get install -y jq gawk tesseract-ocr imagemagick fonts-dejavu

    mkdir -p /app

    # Generate /app/query_spec.png
    convert -size 600x400 xc:white -font DejaVu-Sans -pointsize 20 -fill black -annotate +20+40 "AGGREGATION PIPELINE:\n1. Match status == 'active'\n2. Group by department\n3. Sum salary as total_salary\n4. Sort by total_salary DESC\n5. Limit to top 5 results" /app/query_spec.png

    # Generate /app/data.jsonl
    cat << 'EOF' > /app/generate_data.py
import json
import random

departments = ["HR", "Engineering", "Marketing", "Sales", "Finance", "IT", "Legal", "Operations", "Product", "Design"]
statuses = ["active", "inactive", "pending"]

with open("/app/data.jsonl", "w") as f:
    for i in range(50000):
        record = {
            "id": i,
            "department": random.choice(departments),
            "salary": random.randint(30000, 200000),
            "status": random.choice(statuses)
        }
        f.write(json.dumps(record) + "\n")
EOF
    python3 /app/generate_data.py
    rm /app/generate_data.py

    # Generate /app/baseline.sh
    cat << 'EOF' > /app/baseline.sh
#!/bin/bash
declare -A sums
while read -r line; do
    [[ "$line" =~ \"status\":\ \"([^\"]+)\" ]]
    status="${BASH_REMATCH[1]}"
    if [ "$status" = "active" ]; then
        [[ "$line" =~ \"department\":\ \"([^\"]+)\" ]]
        dept="${BASH_REMATCH[1]}"
        [[ "$line" =~ \"salary\":\ ([0-9]+) ]]
        salary="${BASH_REMATCH[1]}"

        # Unoptimized subshell to simulate slow junior developer code
        dummy=$(echo "$dept")

        sums["$dept"]=$(( sums["$dept"] + salary ))
    fi
done < /app/data.jsonl

tmp=$(mktemp)
for dept in "${!sums[@]}"; do
    echo "$dept ${sums[$dept]}" >> "$tmp"
done
sort -k2 -nr "$tmp" | head -n 5 | awk '{printf "{\"department\": \"%s\", \"total_salary\": %s}\n", $1, $2}' | jq -s .
rm "$tmp"
EOF
    chmod +x /app/baseline.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
