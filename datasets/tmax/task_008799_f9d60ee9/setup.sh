#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps
pip3 install pytest

mkdir -p /home/user/logs
mkdir -p /home/user/scripts

# Create Service A logs
cat << 'EOF' > /home/user/logs/service_a.log
2023-10-25T14:00:00Z System initialized
2023-10-25T14:05:00Z Connection established
EOF

# Create Service B logs
cat << 'EOF' > /home/user/logs/service_b.log
2023-10-25 10:01:00-04:00 Authentication request received
2023-10-25 10:06:00-04:00 User logged in successfully
EOF

# Create Service C logs
cat << 'EOF' > /home/user/logs/service_c.log
1698242520 Database query started
1698242820 Database query completed
EOF

# Background process holding the file
cat << 'EOF' > /home/user/scripts/service_c_emitter.sh
#!/bin/bash
tail -f /home/user/logs/service_c.log > /dev/null
EOF
chmod +x /home/user/scripts/service_c_emitter.sh

# Create the buggy aggregate.sh script
cat << 'EOF' > /home/user/scripts/aggregate.sh
#!/bin/bash
cat /home/user/logs/service_a.log /home/user/logs/service_b.log /home/user/logs/service_c_recovered.log > /tmp/combined.log
sort /tmp/combined.log > /home/user/logs/unified.log
EOF
chmod +x /home/user/scripts/aggregate.sh

# Set up an init script to start the emitter and delete the log file at runtime
# (Doing this in %post would hang the build or not survive into the container)
cat << 'EOF' > /.singularity.d/env/99-init.sh
if ! pgrep -f service_c_emitter >/dev/null 2>&1; then
    bash -c 'exec -a service_c_emitter /home/user/scripts/service_c_emitter.sh' >/dev/null 2>&1 &
    sleep 0.5
    rm -f /home/user/logs/service_c.log
fi
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
