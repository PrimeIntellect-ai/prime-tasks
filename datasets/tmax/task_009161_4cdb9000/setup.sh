#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk strace dos2unix coreutils
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/bad_bin

    cat << 'EOF' > /home/user/bad_bin/awk
#!/bin/bash
# Broken awk that just silently fails
exit 1
EOF
    chmod +x /home/user/bad_bin/awk

    echo -ne "1600000000,1\r\n1600000060,1\r\n1600000120,0\r\n1600000180,1\r\n" | base64 > /home/user/logs/ping_data.b64

    cat << 'EOF' > /home/user/uptime_monitor.sh
#!/bin/bash

# Inject a bad path to simulate a dependency conflict
export PATH="/home/user/bad_bin:$PATH"

LOG_FILE="/home/user/logs/ping_data.b64"

# Decode the base64 log
DECODED=$(base64 -d "$LOG_FILE")

# Calculate total and successful pings
TOTAL=$(echo "$DECODED" | awk -F, 'BEGIN{c=0} {if($2!="") c++} END{print c}')
SUCCESS=$(echo "$DECODED" | awk -F, 'BEGIN{c=0} {if($2==1) c++} END{print c}')

# Calculate uptime percentage (Bug: Integer division rounds to 0 before multiplying by 100)
UPTIME=$(( SUCCESS / TOTAL * 100 ))

echo "Uptime: ${UPTIME}%" > /home/user/uptime_report.txt
EOF
    chmod +x /home/user/uptime_monitor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
