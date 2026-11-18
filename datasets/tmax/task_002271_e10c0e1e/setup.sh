#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 lsof procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create the initial database and insert values
    sqlite3 /home/user/sensor_data.db "CREATE TABLE measurements (id INTEGER PRIMARY KEY, value REAL);"
    sqlite3 /home/user/sensor_data.db "INSERT INTO measurements (value) VALUES (10.1);"
    sqlite3 /home/user/sensor_data.db "INSERT INTO measurements (value) VALUES (20.2);"
    sqlite3 /home/user/sensor_data.db "INSERT INTO measurements (value) VALUES (30.300000000000004);"

    chown user:user /home/user/sensor_data.db

    # Create the background script
    cat << 'EOF' > /home/user/run_sensor.sh
#!/bin/bash
# Open the file on file descriptor 3
exec 3< /home/user/sensor_data.db
# Unlink the file
rm -f /home/user/sensor_data.db
# Keep the process alive to hold the file descriptor open
while true; do sleep 60; done
EOF

    chmod +x /home/user/run_sensor.sh
    chown user:user /home/user/run_sensor.sh

    # Ensure the background process starts when the container is executed
    cat << 'EOF' > /.singularity.d/env/99-start-sensor.sh
#!/bin/sh
if ! pgrep -f "run_sensor.sh" > /dev/null 2>&1; then
    nohup /home/user/run_sensor.sh > /dev/null 2>&1 &
    sleep 0.5
fi
EOF
    chmod +x /.singularity.d/env/99-start-sensor.sh

    chmod -R 777 /home/user
