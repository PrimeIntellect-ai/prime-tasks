#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas jinja2

    mkdir -p /home/user/sensor_logs

    # Create CSV data
    cat << 'EOF' > /home/user/sensor_logs/data1.csv
timestamp,sensor_id,temperature
2023-10-01T10:00:00Z,S1,22.5
2023-10-01T10:05:00Z,S1,22.6
2023-10-01T10:10:00Z,S1,22.4
2023-10-01T10:15:00Z,S1,22.7
2023-10-01T10:20:00Z,S1,45.0
2023-10-01T10:25:00Z,S1,22.5
EOF

    # Create JSON data
    cat << 'EOF' > /home/user/sensor_logs/data2.json
[
  {"timestamp": "2023-10-01T10:00:00Z", "sensor_id": "S2", "temperature": 15.0},
  {"timestamp": "2023-10-01T10:05:00Z", "sensor_id": "S2", "temperature": 15.2},
  {"timestamp": "2023-10-01T10:10:00Z", "sensor_id": "S2", "temperature": -10.0},
  {"timestamp": "2023-10-01T10:15:00Z", "sensor_id": "S2", "temperature": 15.1},
  {"timestamp": "2023-10-01T10:20:00Z", "sensor_id": "S2", "temperature": 14.9},
  {"timestamp": "2023-10-01T10:25:00Z", "sensor_id": "S2", "temperature": 15.0}
]
EOF

    # Create Jinja2 Template (using placeholders to avoid Apptainer build variable syntax)
    cat << 'EOF' > /home/user/report_template.j2
<html>
<head><title>Anomaly Report</title></head>
<body>
    <h1>Detected Anomalies</h1>
    <ul>
    {% for row in anomalies %}
        <li>_OPEN_ row.timestamp _CLOSE_ - _OPEN_ row.sensor_id _CLOSE_: _OPEN_ row.temperature _CLOSE_</li>
    {% endfor %}
    </ul>
</body>
</html>
EOF

    # Replace placeholders with actual curly braces using octal escapes
    sed -i "s/_OPEN_/$(printf '\173\173')/g" /home/user/report_template.j2
    sed -i "s/_CLOSE_/$(printf '\175\175')/g" /home/user/report_template.j2

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
