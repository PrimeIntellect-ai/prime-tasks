#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr bc gawk
    pip3 install pytest

    mkdir -p /app

    # Create the image using ImageMagick
    convert -background white -fill black -pointsize 24 label:"System Parameters:\nAlpha: 2.5\nBeta: 10.4\nDo not change." /app/system_specs.png

    # Create the raw metrics log
    cat << 'EOF' > /app/raw_metrics.log
2023-10-01 10:00:00 [INFO] Starting subsystem
2023-10-01 10:01:00 [METRIC] req_id=123 CPU_Load=10 Response_Latency=45.5 status=OK
2023-10-01 10:02:00 [METRIC] req_id=124 CPU_Load=20 Response_Latency=85.0 status=OK
2023-10-01 10:02:30 [ERROR] req_id=125 CPU_Load=100 Response_Latency=999.9 status=FAIL
2023-10-01 10:03:00 [METRIC] req_id=126 CPU_Load=30 Response_Latency=125.5 status=OK
2023-10-01 10:04:00 [METRIC] req_id=127 CPU_Load=40 Response_Latency=164.0 status=OK
2023-10-01 10:04:15 [METRIC] req_id=128 CPU_Load=40 TIMEOUT
2023-10-01 10:05:00 [METRIC] req_id=129 CPU_Load=50 Response_Latency=205.5 status=OK
EOF

    # Create the oracle script
    cat << 'EOF' > /app/oracle_predictor.sh
#!/bin/bash
LOAD=$1
echo "$LOAD" | awk '{printf "%.3f\n", 2.5 * (4.86 * $1 - 20.70) + 10.4}'
EOF
    chmod +x /app/oracle_predictor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
