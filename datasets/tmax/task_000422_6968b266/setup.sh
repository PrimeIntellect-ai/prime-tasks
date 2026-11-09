#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /app/backend1
    mkdir -p /app/backend2
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
if [ -z "$BACKEND1_PORT" ] || [ -z "$BACKEND2_PORT" ]; then
    echo "Ports not set"
    exit 1
fi
cd /app/backend1 && python3 -m http.server $BACKEND1_PORT &
cd /app/backend2 && python3 -m http.server $BACKEND2_PORT &
EOF
    chmod +x /app/start_services.sh

    # Create clean corpus
    for i in 1 2 3 4 5; do
        echo "{\"id\": $i, \"status\": \"ok\"}" > /app/corpus/clean/clean_$i.json
    done

    # Create evil corpus
    # 2 files > 10KB
    printf '{"data": "%*s"}' 11000 "" | tr ' ' 'A' > /app/corpus/evil/large1.json
    printf '{"data": "%*s"}' 11000 "" | tr ' ' 'B' > /app/corpus/evil/large2.json

    # 3 files with traversal
    echo '{"path": "../etc/passwd"}' > /app/corpus/evil/trav1.json
    echo '{"path": "..\\windows\\system32"}' > /app/corpus/evil/trav2.json
    echo '{"file": "../../secret"}' > /app/corpus/evil/trav3.json

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
