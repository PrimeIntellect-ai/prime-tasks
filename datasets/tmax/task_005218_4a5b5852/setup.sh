#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc tzdata
    pip3 install pytest

    mkdir -p /home/user/app/data /home/user/app/output

    cat << 'EOF' > /home/user/app/supervisor.sh
#!/bin/bash
# Supervisor
rm -rf /home/user/app/data/* /home/user/app/output/*
/home/user/app/sensor.sh &
PID1=$!
TZ="America/New_York" /home/user/app/processor.sh &
PID2=$!

wait $PID1
wait $PID2
EOF
    chmod +x /home/user/app/supervisor.sh

    cat << 'EOF' > /home/user/app/sensor.sh
#!/bin/bash
sleep 1 # Simulate boot time
TODAY=$(TZ=UTC date +%Y-%m-%d)
for i in {1..20}; do
  echo "DATA payload for $TODAY" > /home/user/app/data/log_$i.txt
done
touch /home/user/app/data/ready.flag
EOF
    chmod +x /home/user/app/sensor.sh

    cat << 'EOF' > /home/user/app/processor.sh
#!/bin/bash
# Needs to wait for ready.flag (agent must fix this)

if [ ! -f /home/user/app/data/ready.flag ]; then
  echo "Error: Data not ready!"
  exit 1
fi

TODAY=$(date +%Y-%m-%d) # Will be wrong unless TZ is fixed

for file in /home/user/app/data/log_*.txt; do
  if grep -q "$TODAY" "$file"; then
    sleep 0.5 # Simulate heavy processing
    cp "$file" "/home/user/app/output/$(basename "$file")"
  fi
done
EOF
    chmod +x /home/user/app/processor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
