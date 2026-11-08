#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3 curl build-essential
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:${PATH}"

    mkdir -p /app/corpora/clean /app/corpora/evil
    mkdir -p /home/user/bin

    # Generate evil corpus
    cat << 'EOF' > /app/corpora/evil/sqli.txt
User login failed: admin' OR 1=1 --
Error near DROP TABLE users;
Failed query: unIOn SElect * from passwords
EOF
    cat << 'EOF' > /app/corpora/evil/xss.txt
Comment posted: <script>alert(1)</script>
Avatar URL: JaVaScRiPt:alert(1)
EOF
    echo -e "User agent: \x1B[2J\x1B[H" > /app/corpora/evil/ansi.txt

    # Generate clean corpus
    cat << 'EOF' > /app/corpora/clean/normal.txt
User login failed: admin
User agent: Mozilla/5.0
Page loaded in 200ms
Query executed: select * from items where id=5
EOF

    # Generate Video
    ffmpeg -f lavfi -i color=c=black:s=320x240:d=10 -r 1 \
    -vf "drawbox=x=0:y=0:w=50:h=50:color=red:t=fill:enable='between(t,3,4)+between(t,7,8)'" \
    -c:v libx264 -y /app/dashboard_recording.mp4

    # Generate SQLite DB
    sqlite3 /app/raw_logs.db << 'EOF'
CREATE TABLE logs(id INTEGER, timestamp_sec INTEGER, message TEXT);
INSERT INTO logs VALUES(1, 2, 'Normal background noise');
INSERT INTO logs VALUES(2, 3, 'Anomaly trace 1');
INSERT INTO logs VALUES(3, 3, 'Attacker trace <script>malware</script>');
INSERT INTO logs VALUES(4, 5, 'Normal activity');
INSERT INTO logs VALUES(5, 7, 'Anomaly trace 2');
INSERT INTO logs VALUES(6, 7, 'Attacker DROP TABLE logs');
EOF

    useradd -m -s /bin/bash user || true

    # Copy rust to user
    cp -r /root/.cargo /home/user/.cargo
    cp -r /root/.rustup /home/user/.rustup
    chown -R user:user /home/user/.cargo /home/user/.rustup
    echo 'export PATH="/home/user/.cargo/bin:${PATH}"' >> /home/user/.bashrc

    chmod -R 777 /home/user
    chmod -R 777 /app
