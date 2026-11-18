#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang netcat-openbsd iproute2 logrotate
pip3 install pytest

mkdir -p /home/user/corpus/clean /home/user/corpus/evil /home/user/backups/quarantine /app

# Generate clean corpus
for i in $(seq 1 20); do
  printf "Booting from ROM...\nLoading kernel...\nsshd started\nLogin prompt\n" > /home/user/corpus/clean/log_$i.log
done

# Generate evil corpus (Monitor escape)
for i in $(seq 1 7); do
  printf "kernel boot\n\x01c\nsystem_reset\nrebooting\n" > /home/user/corpus/evil/ev_mon_$i.log
done

# Generate evil corpus (OOM)
for i in $(seq 1 7); do
  printf "kernel boot\nOut of memory: Killed process 1234 (sshd)\nkernel panic\n" > /home/user/corpus/evil/ev_oom_$i.log
done

# Generate evil corpus (Hex A's)
for i in $(seq 1 6); do
  printf "kernel boot\nPayload: 4141414141414141414141414141414141414141\nsegfault\n" > /home/user/corpus/evil/ev_buf_$i.log
done

# Create multi-service compose mock
cat << 'EOF' > /app/start_services.sh
#!/bin/bash
# Aggregator
nohup bash -c 'while true; do nc -l -p 5000 >> /tmp/aggregated.log; done' >/dev/null 2>&1 &
# Generator
nohup bash -c 'while true; do echo "QEMU log entry $(date)" >> /tmp/qemu.log; sleep 1; done' >/dev/null 2>&1 &
EOF
chmod +x /app/start_services.sh
/app/start_services.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
