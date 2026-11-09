#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git bc
pip3 install pytest

mkdir -p /home/user/monitor/data
cd /home/user/monitor

# Create the initial working script
cat << 'EOF' > uptime_monitor.sh
#!/bin/bash
source /home/user/monitor/config.env

if [ -z "$API_KEY" ]; then
    echo "Error: API_KEY is missing."
    exit 1
fi

# Simulate API Check
if [ "$API_KEY" = "SRE_secret_8841a" ]; then
    API_STATUS="OK"
else
    API_STATUS="UNAUTHORIZED"
    echo "Invalid API Key"
    exit 1
fi

# Simulated network ping with retries
ping_success=false
retries=0
max_retries=3

while [ $retries -lt $max_retries ]; do
    # Simulating a random network failure that always fails in this mock
    if [ "$retries" -eq 999 ]; then
        ping_success=true
        break
    fi
    echo "Ping failed, retrying..."

    # BUG: The following line is missing in the buggy version
    retries=$((retries + 1))
done

if [ "$ping_success" = false ]; then
    echo "Network unreachable after $max_retries attempts."
    # We continue anyway to generate the report based on historical data
fi

# Calculate average uptime from log
total=0
count=0
while IFS="|" read -r date uptime; do
    if [[ ! "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Corrupted date format detected: $date"
        exit 1
    fi
    total=$(echo "$total + $uptime" | bc)
    count=$((count + 1))
done < /home/user/monitor/data/uptime.log

if [ $count -gt 0 ]; then
    avg=$(echo "scale=2; $total / $count" | bc)
else
    avg=0
fi

echo "API_STATUS=$API_STATUS" > /home/user/monitor/report.txt
echo "Average Uptime=$avg" >> /home/user/monitor/report.txt
echo "Report generated successfully."
EOF

chmod +x uptime_monitor.sh

# Create the initial config
cat << 'EOF' > config.env
API_KEY="SRE_secret_8841a"
ENDPOINT="https://api.monitoring.local/v1/status"
EOF

# Create the initial valid log
cat << 'EOF' > data/uptime.log
2023-10-01|99.9
2023-10-02|100.0
2023-10-03|99.5
2023-10-04|98.2
EOF

# Initialize Git and make the first commit
git init
git add uptime_monitor.sh config.env data/uptime.log
git config user.name "Admin"
git config user.email "admin@local"
git commit -m "Initial commit with working monitoring system"

# Introduce the bug and remove the secret
cat << 'EOF' > config.env
API_KEY=""
ENDPOINT="https://api.monitoring.local/v1/status"
EOF

# Remove the increment line from the script to create the infinite loop
sed -i '/retries=$((retries + 1))/d' uptime_monitor.sh

git add uptime_monitor.sh config.env
git commit -m "Update retry logic and scrub secrets"

# Corrupt the database file (uncommitted)
cat << 'EOF' >> data/uptime.log
2023-10-05|ERR^&GARBAGE
2023-10-06|99.1
NULL_DATE|0.00
2023-10-07|100.0
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/monitor
chmod -R 777 /home/user
