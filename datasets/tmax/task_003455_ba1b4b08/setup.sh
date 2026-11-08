#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

mkdir -p /app/corpora/clean /app/corpora/evil /home/user/samples

# Compile the legacy signature checker
cat << 'EOF' > /tmp/sig_check.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 4) return 1;
    long long ts = atoll(argv[1]);
    long long sid = atoll(argv[2]);
    long long meas = atoll(argv[3]);
    long long sig = (ts + (sid * 7) + meas) % 9999;
    printf("%lld\n", sig);
    return 0;
}
EOF
gcc -O2 /tmp/sig_check.c -o /app/sig_check
strip /app/sig_check

# Generate clean corpus (averages <= 500, correct signatures)
for i in $(seq 1 5); do
  echo "timestamp,sensor_id,measurement,signature" > /app/corpora/clean/clean_$i.csv
  for j in $(seq 1 20); do
    ts=$((1600000000 + j * 10))
    sid=$((i))
    meas=$((100 + j * 5))
    sig=$(((ts + sid * 7 + meas) % 9999))
    echo "$ts,$sid,$meas,$sig" >> /app/corpora/clean/clean_$i.csv
  done
done

# Generate evil corpus 1: high rolling average
echo "timestamp,sensor_id,measurement,signature" > /app/corpora/evil/evil_1.csv
for j in $(seq 1 5); do
  ts=$((1600000000 + j * 10))
  sid=99
  meas=600 # 3 of these will average > 500
  sig=$(((ts + sid * 7 + meas) % 9999))
  echo "$ts,$sid,$meas,$sig" >> /app/corpora/evil/evil_1.csv
done

useradd -m -s /bin/bash user || true

# Copy some samples for the user
cp /app/corpora/clean/clean_1.csv /home/user/samples/sample_clean.csv
cp /app/corpora/evil/evil_1.csv /home/user/samples/sample_evil.csv
chown -R user:user /home/user/samples
chmod +x /app/sig_check

chmod -R 777 /home/user
