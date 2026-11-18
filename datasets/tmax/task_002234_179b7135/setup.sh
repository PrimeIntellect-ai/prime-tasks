#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc locales gawk
    pip3 install pytest

    # Generate the locale used in the broken script
    locale-gen fr_FR.UTF-8

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/measurements.csv
timestamp,sensor_name,value
2023-10-01T12:00:00,Alpha,23.5
2023-10-01T12:01:00,Beta,-2.1
2023-10-01T12:02:00,Alpha,
2023-10-01T12:03:00,Gamma,45.2
2023-10-01T12:04:00,Alpha,24.1
2023-10-01T12:05:00,Beta,999.9
2023-10-01T12:06:00,Beta,5.5
2023-10-01T12:07:00,Gamma,48.0
2023-10-01T12:08:00,Alpha,-50.0
2023-10-01T12:09:00,Alpha,22.0
2023-10-01T12:10:00,Gamma,
2023-10-01T12:11:00,Beta,4.0
2023-10-01T12:12:00,Gamma,42.8
EOF

    cat << 'EOF' > /home/user/analyze.sh
#!/bin/bash
# Broken script
export LC_NUMERIC=fr_FR.UTF-8 # Misconfiguration causing float issues with standard dot notation

rm -f /home/user/sensor_report.txt
tail -n +2 /home/user/measurements.csv | while IFS=, read -r ts sensor val; do
  # No missing value handling
  # No outlier handling
  echo "$sensor:$val" >> /tmp/processing.tmp
done
# ... Rest is intentionally broken ...
EOF

    chmod +x /home/user/analyze.sh
    chmod -R 777 /home/user
