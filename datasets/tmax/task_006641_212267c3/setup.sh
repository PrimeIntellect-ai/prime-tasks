#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip parallel
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/batch1.csv
PatientID,Name,SSN,Age,BloodPressure,HeartRate
1,John Doe,123-45-6789,45,110/70,65
2,Jane Smith,987-65-4321,130,120/80,70
3,Bob Jones,111-22-3333,34,,
4,Alice Brown,invalid-ssn,29,115/75,80
5,Charlie Day,222-33-4444,-5,100/60,90
6,Diana Prince,555-66-7777,28,,85
EOF

    cat << 'EOF' > /home/user/raw_data/batch2.csv
PatientID,Name,SSN,Age,BloodPressure,HeartRate
7,Evan Wright,999-88-7777,50,130/85,
8,Fiona Gallagher,444-55-6666,120,,
9,George Costanza,000-00-0000,abc,120/80,72
10,Hannah Abbott,123-12-1234,0,90/60,100
EOF

    chmod -R 777 /home/user
