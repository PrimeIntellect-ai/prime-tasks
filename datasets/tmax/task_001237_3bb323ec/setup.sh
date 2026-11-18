#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go ffmpeg zip curl
pip3 install pytest

# Create user
useradd -m -s /bin/bash user || true

# Create config.yaml
cat << 'EOF' > /home/user/config.yaml
prefixes:
  - "backup_"
  - "metrics_"
EOF

# Create archives
mkdir -p /home/user/archives
cd /home/user/archives

# Valid archives
echo "backup1" > backup_1.txt
tar -czf backup_1.tar.gz backup_1.txt
rm backup_1.txt

echo "metrics1" > metrics_1.txt
tar -czf metrics_1.tar.gz metrics_1.txt
rm metrics_1.txt

echo "random1" > random_1.txt
tar -czf random_1.tar.gz random_1.txt
rm random_1.txt

# Corrupt archives
echo "corrupted data" > backup_2.tar.gz
echo "corrupted data" > old_data.tar.gz

cd /

# Create storage.wal
cat << 'EOF' > /home/user/storage.wal
2023-10-01 10:00:00 INFO Startup
2023-10-01 10:05:00 ERROR Disk full
  Traceback...
  ErrID: 123e4567-e89b-12d3-a456-426614174000
2023-10-01 10:10:00 INFO Cleanup
2023-10-01 10:15:00 ERROR Permission denied
  ErrID: 987e6543-e21b-12d3-a456-426614174000
2023-10-01 10:16:00 ERROR Same error
  ErrID: 123e4567-e89b-12d3-a456-426614174000
EOF

# Create test video
mkdir -p /app
ffmpeg -f lavfi -i testsrc=duration=10:size=320x240:rate=30 -pix_fmt yuv420p /app/storage_scan.mp4

chmod -R 777 /home/user
chmod -R 777 /app
