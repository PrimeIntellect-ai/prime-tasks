#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/debug_env/logs

    echo "INFO: App started successfully." > "/home/user/debug_env/logs/app_startup.log"
    echo "CRITICAL: Container crashed. Reason: OOMKilled_Memory_Limit_Exceeded" > "/home/user/debug_env/logs/crash report.log"
    echo "WARN: High latency detected." > "/home/user/debug_env/logs/performance monitor.log"

    cat << 'EOF' > /home/user/debug_env/logs/network_trace.txt
10:20:30.123456 IP 192.168.1.50.12345 > 10.0.0.1.80: Flags [P.], seq 1:20, ack 1, win 500, length 19
E..//.@.@..|.....
......P...r.P....H..GET / HTTP/1.1..

10:20:31.654321 IP 10.45.99.12.54321 > 10.0.0.1.8080: Flags [P.], seq 1:40, ack 1, win 500, length 39
E..C/.@.@..|
.-c.....P...r.P....H..POST /api/v1 MALICIOUS_PAYLOAD
EOF

    cat << 'EOF' > /home/user/debug_env/process_logs.sh
#!/bin/bash
cd /home/user/debug_env

source .env

rm -f combined.txt

# BUG: Unquoted variable in for loop breaks on spaces
for log_file in $(ls logs/*.log); do
    echo "Processing $log_file"
    cat "$log_file" >> combined.txt
done

echo "Extracting malicious packets..."
# BUG: The environment variable is broken
grep "$PCAP_FILTER_TERM" logs/network_trace.txt > malicious_packets.txt

echo "Done."
EOF

    chmod +x /home/user/debug_env/process_logs.sh

    cat << 'EOF' > /home/user/debug_env/.env
# Misconfigured term
PCAP_FILTER_TERM="--invalid-flag-MALICIOUS"
EOF

    chown -R user:user /home/user/debug_env
    chmod -R 777 /home/user
