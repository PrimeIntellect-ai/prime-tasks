#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip procps
pip3 install pytest

mkdir -p /home/user/app_data/subdir /home/user/logs /home/user/bin

dd if=/dev/zero of=/home/user/app_data/file1.dat bs=1M count=5
dd if=/dev/zero of=/home/user/app_data/subdir/file2.dat bs=1M count=2

cat << 'EOF' > /home/user/bin/background_worker.sh
#!/bin/bash
while true; do sleep 60; done
EOF
chmod +x /home/user/bin/background_worker.sh

# Mock ps and pgrep to simulate running background workers
# since background processes do not persist across Apptainer exec/build boundaries
mv /bin/ps /bin/ps.orig
cat << 'EOF' > /bin/ps
#!/bin/bash
/bin/ps.orig "$@"
echo "user 1234 0.0 0.0 1000 1000 ? S 00:00:00 /bin/bash /home/user/bin/background_worker.sh"
echo "user 1235 0.0 0.0 1000 1000 ? S 00:00:00 /bin/bash /home/user/bin/background_worker.sh"
echo "user 1236 0.0 0.0 1000 1000 ? S 00:00:00 /bin/bash /home/user/bin/background_worker.sh"
EOF
chmod +x /bin/ps

mv /usr/bin/pgrep /usr/bin/pgrep.orig
cat << 'EOF' > /usr/bin/pgrep
#!/bin/bash
if [[ "$*" == *"background_worker.sh"* ]]; then
  echo "1234"
  echo "1235"
  echo "1236"
else
  /usr/bin/pgrep.orig "$@"
fi
EOF
chmod +x /usr/bin/pgrep

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
