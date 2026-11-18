#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/run_test.sh
#!/bin/bash
# Test script for edge monitor

PID_FILE="/home/user/sensor.pid"

# Start dummy process
sleep 100 &
DUMMY_PID=$!
echo $DUMMY_PID > $PID_FILE

echo "Running monitor while process is alive..."
/home/user/monitor $PID_FILE

# Kill dummy process
kill $DUMMY_PID
wait $DUMMY_PID 2>/dev/null

echo "Running monitor after process died..."
/home/user/monitor $PID_FILE
EOF
    chmod +x /home/user/run_test.sh

    chmod -R 777 /home/user
