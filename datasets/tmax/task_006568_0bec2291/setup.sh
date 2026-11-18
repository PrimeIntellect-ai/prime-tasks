#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang gawk grep coreutils
    pip3 install pytest

    mkdir -p /home/user/mock_containers
    cat << 'EOF' > /home/user/container_mgr.sh
#!/bin/bash

STATE_DIR="/home/user/mock_containers"

if [ ! -d "$STATE_DIR/init" ]; then
    mkdir -p "$STATE_DIR/init"
    # Container 1: Normal
    echo "250MB" > "$STATE_DIR/c1_mem"
    echo -e "[INFO] Started.\n[ERROR] Dashboard UI Error: Widget 'Network' timeout.\n[INFO] Running." > "$STATE_DIR/c1_logs"
    echo "abc10001" > "$STATE_DIR/c1_id"

    # Container 2: High Memory
    echo "800MB" > "$STATE_DIR/c2_mem"
    echo -e "[INFO] Started.\n[ERROR] Dashboard UI Error: Out of memory in panel 'Disk'.\n[WARN] High load." > "$STATE_DIR/c2_logs"
    echo "def20002" > "$STATE_DIR/c2_id"

    # Container 3: Normal, no errors
    echo "150MB" > "$STATE_DIR/c3_mem"
    echo -e "[INFO] Started.\n[INFO] Health check passed." > "$STATE_DIR/c3_logs"
    echo "ghi30003" > "$STATE_DIR/c3_id"

    # Container 4: High Memory, multiple errors
    echo "650MB" > "$STATE_DIR/c4_mem"
    echo -e "[INFO] Started.\n[ERROR] Dashboard UI Error: Widget 'CPU' timeout.\n[ERROR] Dashboard UI Error: Alert manager disconnected." > "$STATE_DIR/c4_logs"
    echo "jkl40004" > "$STATE_DIR/c4_id"
fi

COMMAND=$1
ARG=$2

case $COMMAND in
    list)
        echo "CONTAINER ID   IMAGE      STATUS   MEM USAGE"
        echo "$(cat $STATE_DIR/c1_id)       dash-app   Running  $(cat $STATE_DIR/c1_mem)"
        echo "$(cat $STATE_DIR/c2_id)       dash-app   Running  $(cat $STATE_DIR/c2_mem)"
        echo "$(cat $STATE_DIR/c3_id)       dash-api   Running  $(cat $STATE_DIR/c3_mem)"
        echo "$(cat $STATE_DIR/c4_id)       dash-db    Running  $(cat $STATE_DIR/c4_mem)"
        ;;
    logs)
        if [ "$ARG" == "$(cat $STATE_DIR/c1_id)" ]; then cat $STATE_DIR/c1_logs; fi
        if [ "$ARG" == "$(cat $STATE_DIR/c2_id)" ]; then cat $STATE_DIR/c2_logs; fi
        if [ "$ARG" == "$(cat $STATE_DIR/c3_id)" ]; then cat $STATE_DIR/c3_logs; fi
        if [ "$ARG" == "$(cat $STATE_DIR/c4_id)" ]; then cat $STATE_DIR/c4_logs; fi
        ;;
    restart)
        if [ "$ARG" == "$(cat $STATE_DIR/c1_id)" ]; then echo "100MB" > $STATE_DIR/c1_mem; fi
        if [ "$ARG" == "$(cat $STATE_DIR/c2_id)" ]; then echo "100MB" > $STATE_DIR/c2_mem; fi
        if [ "$ARG" == "$(cat $STATE_DIR/c3_id)" ]; then echo "100MB" > $STATE_DIR/c3_mem; fi
        if [ "$ARG" == "$(cat $STATE_DIR/c4_id)" ]; then echo "100MB" > $STATE_DIR/c4_mem; fi
        echo "Container $ARG restarted."
        ;;
    *)
        echo "Unknown command"
        exit 1
        ;;
esac
EOF
    chmod +x /home/user/container_mgr.sh

    # Initialize the state files
    /home/user/container_mgr.sh list > /dev/null

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
