#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/traffic_sim.sh
#!/bin/bash
exec 3> /home/user/service.log

echo '{"timestamp": "2023-10-01T10:00:00Z", "ip": "10.0.0.1", "status": 200, "latency": 45}' >&3
echo '{"timestamp": "2023-10-01T10:00:01Z", "ip": "10.0.0.2", "status": 200, "latency": 32}' >&3
echo '{"timestamp": "2023-10-01T10:00:02Z", "ip": "10.0.0.3", "status": 404, "latency": 12}' >&3
# The anomaly
echo '{"timestamp": "2023-10-01T10:00:03Z", "ip": "192.168.205.77", "status": 500, "latency": 8504}' >&3
echo '{"timestamp": "2023-10-01T10:00:04Z", "ip": "10.0.0.4", "status": 200, "latency": 41}' >&3

# Delete the file to simulate the junior developer's mistake
rm -f /home/user/service.log

# Loop forever to keep the process and file descriptor alive
while true; do
    sleep 10
done
EOF

    chmod +x /home/user/traffic_sim.sh

    # Ensure the script is started when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-start-traffic-sim.sh
if ! pgrep -f traffic_sim.sh > /dev/null 2>&1; then
    nohup /home/user/traffic_sim.sh > /dev/null 2>&1 &
    sleep 1
fi
EOF

    chmod -R 777 /home/user
