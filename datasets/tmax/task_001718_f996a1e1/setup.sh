#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    mkdir -p /home/user/data /home/user/model

    # Create biomarkers.csv
    cat << 'EOF' > /home/user/data/biomarkers.csv
patient_id,bmi,heart_rate
1,24.5,75
2,28.0,160
3,,80
4,22.1,120
5,,155
EOF

    # Create demographics.csv
    cat << 'EOF' > /tmp/demographics.csv
patient_id,age,gender
1,45,M
2,,F
3,60,M
4,35,F
5,70,M
EOF

    cd /tmp
    tar -czf /home/user/data/demographics.tar.gz demographics.csv
    rm demographics.csv
    cd /

    # Create weights.json
    cat << 'EOF' > /home/user/model/weights.json
{
  "age": 0.5,
  "bmi": 1.2,
  "heart_rate": 0.1
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
