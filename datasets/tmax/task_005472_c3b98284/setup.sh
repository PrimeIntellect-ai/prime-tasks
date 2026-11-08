#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/bin
    cat << 'EOF' > /home/user/bin/edge-daemon
#!/bin/bash
# Dummy edge daemon
trap "echo 'Terminating...'; exit 0" SIGTERM
while true; do
    echo "Running in timezone $TZ at $(date)"
    sleep 2
done
EOF
    chmod +x /home/user/bin/edge-daemon

    # Create the log file so it exists for the initial state test
    touch /home/user/daemon-status.log

    # Note: Background processes started in %post will not persist in the final container image.
    # The evaluation framework should ideally start the daemon before testing the agent,
    # or the agent will have to handle the case where it's not initially running.
    # We attempt to start it here just in case.
    nohup /home/user/bin/edge-daemon > /home/user/daemon-status.log 2>&1 &

    chmod -R 777 /home/user
