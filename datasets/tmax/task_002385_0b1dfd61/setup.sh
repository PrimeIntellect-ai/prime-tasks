#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc procps
pip3 install pytest

mkdir -p /home/user/.hidden
cat << 'EOF' > /home/user/records.csv
1,100,200
2,500,600
3,60000,50000
4,-10,20
5,70000,40000
EOF

cat << 'EOF' > /home/user/.hidden/data_holder.py
import time
import sys

def hold_file():
    f = open('/home/user/records.csv', 'r')
    while True:
        time.sleep(10)

if __name__ == '__main__':
    hold_file()
EOF

cat << 'EOF' > /home/user/processor.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if(argc != 3) return 1;

    int base = atoi(argv[1]);
    int mult = atoi(argv[2]);

    if (base < 0 || mult < 0) {
        printf("-1\n");
        return 0;
    }

    // BUG: Signed integer overflow for large numbers
    int result = base * mult;
    printf("%d\n", result);
    return 0;
}
EOF

cat << 'EOF' > /home/user/daemon.py
import sys
import subprocess

def process_record(base, mult):
    res = subprocess.run(
        ["/home/user/processor", str(base), str(mult)], 
        capture_output=True, text=True
    )
    return int(res.stdout.strip())

def aggregate(file_path):
    records = []
    with open(file_path, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) == 3:
                records.append((parts[1], parts[2]))

    total = 0
    history = []
    i = 0

    # BUG: Infinite loop / memory leak when size < 0
    while i < len(records):
        size = process_record(records[i][0], records[i][1])
        if size < 0:
            history.append(0)
            continue

        history.append(size)
        total += size
        i += 1

    return total

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 daemon.py <file>")
        sys.exit(1)

    final_total = aggregate(sys.argv[1])
    # The agent needs to modify this script to write to final_sum.txt
EOF

cat << 'EOF' > /.singularity.d/env/99-start.sh
#!/bin/sh
if ! pgrep -f data_holder.py > /dev/null; then
    nohup python3 /home/user/.hidden/data_holder.py > /dev/null 2>&1 &
    sleep 1
    rm -f /home/user/records.csv
fi
EOF
chmod +x /.singularity.d/env/99-start.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
