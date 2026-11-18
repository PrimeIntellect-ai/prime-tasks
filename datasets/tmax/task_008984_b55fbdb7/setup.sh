#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 coreutils
pip3 install pytest

mkdir -p /home/user/data
mkdir -p /home/user/service

# Create the SQLite database
cd /home/user/data
sqlite3 sensor.db "CREATE TABLE metrics(id INTEGER PRIMARY KEY, sensor_id TEXT, value REAL);"
sqlite3 sensor.db "INSERT INTO metrics(sensor_id, value) VALUES ('S1', 10), ('S1', 20), ('S1', 30), ('S1', 40), ('S1', 50), ('S1', 60);"
sqlite3 sensor.db "INSERT INTO metrics(sensor_id, value) VALUES ('S2', 100), ('S2', 100);"
sqlite3 sensor.db "INSERT INTO metrics(sensor_id, value) VALUES ('S3', 40), ('S3', 40), ('S3', 40), ('S3', 40), ('S3', 40), ('S3', 40);"
sqlite3 sensor.db "INSERT INTO metrics(sensor_id, value) VALUES ('S4', 50), ('S4', 50), ('S4', 50), ('S4', 50), ('S4', 50), ('S4', 50);"
sqlite3 sensor.db "INSERT INTO metrics(sensor_id, value) VALUES ('S5', 10), ('S5', 10), ('S5', 10), ('S5', 10), ('S5', 10), ('S5', 10);"

# Corrupt the header
printf "CORRUPTED_HEADER" | dd of=sensor.db bs=1 count=16 conv=notrunc

# Create the buggy script
cat << 'EOF' > /home/user/service/ingest.sh
#!/bin/bash
# Data Ingestion Service
declare -a BATCH=()

process_batch() {
    echo "Processing batch of ${#BATCH[@]} items..."
    # Dummy processing
    sleep 0.1
}

tail -f /dev/null | while read -r line; do
    # Simulate reading sensor data
    BATCH+=("$line")

    if (( ${#BATCH[@]} >= 10 )); then
        process_batch "${BATCH[@]}"
        # BUG: The array is never cleared, causing a memory leak
        # BATCH=() should be here
    fi
done
EOF
chmod +x /home/user/service/ingest.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
