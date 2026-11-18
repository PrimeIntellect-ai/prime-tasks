#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/cloud_emulator.sh
#!/bin/bash
# Simulates a slow-starting service (e.g., QEMU VM initialization)
sleep 6
python3 -m http.server 8080 --bind 127.0.0.1 >/dev/null 2>&1 &
PY_PID=$!
echo $PY_PID > /tmp/cloud_emulator_py.pid

# Wait for termination signal
trap "kill $PY_PID; exit 0" SIGINT SIGTERM EXIT
wait $PY_PID
EOF
    chmod +x /home/user/cloud_emulator.sh

    cat << 'EOF' > /home/user/cloud_ssh_mock
#!/bin/bash
read -p "Password: " -s pass
echo
if [ "$pass" != "finops2024" ]; then
    echo "Access denied"
    exit 1
fi

while true; do
    echo -n "Emulator> "
    read cmd
    if [ "$cmd" == "fetch_cost" ]; then
        # Check if port 8080 is actually open (simulating dependency)
        if nc -z 127.0.0.1 8080; then
            echo "COST_OPTS: {\"spot\": 0.04, \"on_demand\": 0.12}"
        else
            echo "ERROR: Emulator backend on port 8080 is not reachable. Try again later."
        fi
    elif [ "$cmd" == "exit" ]; then
        exit 0
    else
        echo "Unknown command"
    fi
done
EOF
    chmod +x /home/user/cloud_ssh_mock

    chmod -R 777 /home/user
