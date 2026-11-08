#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    # Create corpus directories
    mkdir -p /opt/corpus/clean
    mkdir -p /opt/corpus/evil

    # Create clean corpus files
    printf "WAL_START\nDATA=1\nWAL_END\n" > /opt/corpus/clean/clean1.wal
    printf "WAL_START\nLOG=UPDATE\nDATA=2\nWAL_END\n" > /opt/corpus/clean/clean2.wal

    # Create evil corpus files
    printf "DATA=1\nWAL_END\n" > /opt/corpus/evil/evil1.wal
    printf "WAL_START\n../etc/passwd\nWAL_END\n" > /opt/corpus/evil/evil2.wal
    printf "WAL_START\nEXEC=rm -rf /\nWAL_END\n" > /opt/corpus/evil/evil3.wal
    printf "WAL_START\nDATA=1" > /opt/corpus/evil/evil4.wal

    # Create user
    useradd -m -s /bin/bash user || true

    # Create services directory and spool directories
    mkdir -p /home/user/services
    mkdir -p /home/user/run/spool/pending
    mkdir -p /home/user/run/spool/processed

    # Create producer script
    cat << 'EOF' > /home/user/services/producer.py
import time, os
os.makedirs("/home/user/run/spool/pending", exist_ok=True)
c = 0
while True:
    with open(f"/home/user/run/spool/pending/f_{c}.wal", "w") as f:
        if c % 2 == 0:
            f.write("WAL_START\nDATA=CLEAN\nWAL_END\n")
        else:
            f.write("WAL_START\nEXEC=BAD\nWAL_END\n")
    c += 1
    time.sleep(2)
EOF

    # Create archiver script
    cat << 'EOF' > /home/user/services/archiver.sh
#!/bin/bash
while True; do
  cd /home/user/run/spool/pending
  if [ "$(ls -A .)" ]; then
     tar -czf /home/user/run/spool/processed/archive_$(date +%s).tar.gz *
     rm *
  fi
  sleep 5
done
EOF

    # Create start script
    cat << 'EOF' > /home/user/services/start.sh
#!/bin/bash
python3 /home/user/services/producer.py &
bash /home/user/services/archiver.sh &
wait
EOF

    chmod +x /home/user/services/archiver.sh
    chmod +x /home/user/services/start.sh

    # Set permissions
    chmod -R 777 /opt/corpus
    chmod -R 777 /home/user
