#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_sensor_data.csv
timestamp,patient_id,patient_name,heart_rate,notes
2023-10-01T10:00:00,SSN-123456789,Alice Smith,75.0,"Patient resting comfortably."
2023-10-01T10:03:00,SSN-123456789,Alice Smith,78.0,"Slight elevation
in heart rate."
2023-10-01T10:05:00,SSN-123456789,Alice Smith,76.0,"Stabilized."
2023-10-01T10:00:00,SSN-987654321,Bob Jones,82.0,"Complained of
dizziness
and fatigue."
2023-10-01T10:02:00,SSN-987654321,Bob Jones,85.0,"Administered water."
2023-10-01T10:04:00,SSN-987654321,Bob Jones,80.0,"Patient asleep."
EOF

    chmod -R 777 /home/user
