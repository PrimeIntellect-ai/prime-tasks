#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl jq
    pip3 install pytest numpy scipy pandas

    mkdir -p /app
    mkdir -p /home/user

    # Create config.env with missing values
    cat << 'EOF' > /app/config.env
REDIS_HOST=
REDIS_PORT=
WEB_API_URL=
EOF

    # Create start_stack.sh
    cat << 'EOF' > /app/start_stack.sh
#!/bin/bash
source /app/config.env
echo "Starting Redis on $REDIS_HOST:$REDIS_PORT..."
echo "Starting Web API at $WEB_API_URL..."
echo "Starting Worker..."
echo "Stack started successfully."
EOF
    chmod +x /app/start_stack.sh

    # Create run_load.sh
    cat << 'EOF' > /app/run_load.sh
#!/bin/bash
source /app/config.env

if [ "$REDIS_HOST" == "127.0.0.1" ] && [ "$REDIS_PORT" == "6379" ] && [ "$WEB_API_URL" == "http://127.0.0.1:5000" ]; then
    echo "Running load test..."
    cat << 'CSVEOF' > /home/user/metrics.csv
Time_s,Requests_Per_Sec,Latency_ms,CPU_util
0.0,10,15.0,20.0
1.0,20,35.0,30.0
2.0,30,65.0,45.0
3.0,40,105.0,65.0
4.0,50,155.0,90.0
5.0,60,215.0,120.0
CSVEOF
    echo "Load test complete. Metrics saved to /home/user/metrics.csv."
else
    echo "Error: Services not correctly configured. Please check /app/config.env"
    exit 1
fi
EOF
    chmod +x /app/run_load.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
