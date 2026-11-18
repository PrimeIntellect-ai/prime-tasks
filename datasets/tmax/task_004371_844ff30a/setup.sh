#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 ffmpeg zbar-tools qrencode socat netcat-openbsd
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Create SQLite database
    sqlite3 /app/compliance.db << 'EOF'
CREATE TABLE employees (id INTEGER PRIMARY KEY, emp_id TEXT, name TEXT, clearance TEXT);
CREATE TABLE room_access (id INTEGER PRIMARY KEY, emp_id TEXT, room TEXT, timestamp TEXT);

INSERT INTO employees (emp_id, name, clearance) VALUES ('EMP042', 'Alice', 'SECRET');
INSERT INTO employees (emp_id, name, clearance) VALUES ('EMP017', 'Bob', 'SECRET');
INSERT INTO employees (emp_id, name, clearance) VALUES ('EMP999', 'Charlie', 'TOP_SECRET');
INSERT INTO employees (emp_id, name, clearance) VALUES ('EMP001', 'Dave', 'SECRET');

INSERT INTO room_access (emp_id, room, timestamp) VALUES ('EMP042', 'ServerRoom', '2023-10-01 10:00:00');
INSERT INTO room_access (emp_id, room, timestamp) VALUES ('EMP017', 'ServerRoom', '2023-10-01 10:05:00');
INSERT INTO room_access (emp_id, room, timestamp) VALUES ('EMP999', 'ServerRoom', '2023-10-01 10:10:00');
EOF

    # Generate QR codes and video fixture
    cd /app
    qrencode -s 10 -o emp111.png "EMP111"
    qrencode -s 10 -o emp801.png "EMP801"
    qrencode -s 10 -o emp805.png "EMP805"
    qrencode -s 10 -o emp222.png "EMP222"

    ffmpeg -f lavfi -i color=c=white:s=640x480:r=30:d=35 \
        -i emp111.png -i emp801.png -i emp805.png -i emp222.png \
        -filter_complex "[0:v][1:v]overlay=x=100:y=100:enable='between(t,4,6)'[v1]; \
                         [v1][2:v]overlay=x=100:y=100:enable='between(t,12,14)'[v2]; \
                         [v2][3:v]overlay=x=100:y=100:enable='between(t,20,22)'[v3]; \
                         [v3][4:v]overlay=x=100:y=100:enable='between(t,29,31)'[out]" \
        -map "[out]" -c:v libx264 -preset ultrafast -y /app/server_room_cam.mp4

    rm /app/*.png

    # Create initial script
    cat << 'EOF' > /home/user/run_audit.sh
#!/bin/bash
# BUG: Implicit cross join
sqlite3 /app/compliance.db "SELECT e.emp_id FROM employees e, room_access r WHERE e.clearance != 'TOP_SECRET' AND r.room = 'ServerRoom';"
EOF
    chmod +x /home/user/run_audit.sh

    chmod -R 777 /app
    chmod -R 777 /home/user
