#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk sed coreutils
pip3 install pytest

mkdir -p /home/user/data

cat << 'EOF' > /home/user/data/sensors.tsv
SensorID	Location	Status
S1	Lobby	ACTIVE
S2	Roof	INACTIVE
S3	Basement	ACTIVE	EXTRA_COLUMN
S4	Roof	ACTIVE
S5	Lobby	ACTIVE
S6	Basement	ACTIVE
S7	Garage
EOF

cat << 'EOF' > /home/user/data/measurements.tsv.tmp
SensorID	Timestamp	Value
S1	2023-10-01T10:00	10.5
S1	2023-10-01T11:00	12.0
S2	2023-10-01T10:00	50.0
S4	2023-10-01T10:00	100.1
S4	2023-10-01T12:00	99.5
S5	2023-10-01T10:00	15.0
S6	2023-10-01T10:00	-5.0
S6	2023-10-01T11:00	-2.5
S3	2023-10-01T10:00	999.9
EOF

sed 's/$/\r/' /home/user/data/measurements.tsv.tmp > /home/user/data/measurements.tsv
rm /home/user/data/measurements.tsv.tmp

cat << 'EOF' > /home/user/expected_max_values.tsv
Location	MaxValue
Basement	-2.5
Lobby	15.0
Roof	100.1
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
