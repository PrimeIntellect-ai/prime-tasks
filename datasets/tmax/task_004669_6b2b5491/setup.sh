#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/etl_data.csv
timestamp,record_id,sensor_value
2023-10-01T10:01:00,A2,
2023-10-01T10:00:00,A1,45.5
2023-10-01T10:06:00,A7,110.0
2023-10-01T10:02:00,A3,46.0
2023-10-01T10:01:00,A2,
2023-10-01T10:04:00,A5,
2023-10-01T10:05:00,A6,105.0
2023-10-01T10:02:00,A3,46.0
2023-10-01T10:03:00,A4,45.0
2023-10-01T10:05:00,A6,105.0
EOF

    # Use python to write the template file to avoid Apptainer build variable parsing errors with curly braces
    python3 -c '
with open("/home/user/report_template.txt", "w") as f:
    f.write("ETL Summary Report\n------------------\nAverage Sensor Value: " + chr(123) + chr(123) + "AVG_VALUE" + chr(125) + chr(125) + "\nTotal Anomalies Detected: " + chr(123) + chr(123) + "ANOMALY_COUNT" + chr(125) + chr(125) + "\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
