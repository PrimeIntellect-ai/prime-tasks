#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc unzip zip
    pip3 install pytest

    mkdir -p /home/user/incoming
    cat << 'EOF' > /home/user/generate_logs.sh
#!/bin/bash
mkdir -p /home/user/incoming
rm -f /home/user/incoming/*
rm -f /home/user/bad_logs.csv

for i in {1..10}; do
  status="OK"
  if [ $((i % 3)) -eq 0 ]; then
    status="ERROR"
  fi

  # Write JSON
  echo "{\"id\": $i, \"status\": \"$status\", \"data\": \"payload data for log $i\"}" > /home/user/incoming/log_$i.json

  # Create ZIP
  zip -qj /home/user/incoming/log_$i.zip.tmp /home/user/incoming/log_$i.json

  # Corrupt if ERROR
  if [ "$status" == "ERROR" ]; then
    # Corrupt the zip file by overwriting the first 10 bytes with garbage
    dd if=/dev/urandom of=/home/user/incoming/log_$i.zip.tmp bs=1 count=10 conv=notrunc status=none
  fi

  # Move to final name to trigger a clean IN_CLOSE_WRITE or IN_MOVED_TO
  # We use cp then rm to trigger IN_CLOSE_WRITE for simplicity
  cp /home/user/incoming/log_$i.zip.tmp /home/user/incoming/log_$i.zip
  rm /home/user/incoming/log_$i.zip.tmp

  sleep 0.5
done
EOF
    chmod +x /home/user/generate_logs.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
