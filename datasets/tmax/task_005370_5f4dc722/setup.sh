#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gawk
    pip3 install pytest

    mkdir -p /home/user/data
    mkdir -p /app

    # Generate raw_edges.csv
    python3 -c '
import random
import time

with open("/home/user/data/raw_edges.csv", "w") as f:
    for i in range(500000):
        src = f"192.168.1.{random.randint(1, 250)}"
        dst = f"10.0.0.{random.randint(1, 250)}"
        ts = 1600000000 + random.randint(0, 100000)
        b = random.randint(10, 5000)
        f.write(f"{src},{dst},{ts},{b}\n")
'

    # Create net_scorer C code
    cat << 'EOF' > /app/net_scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[1024];
    while (fgets(line, sizeof(line), stdin)) {
        char src[256], dst[256];
        int ts, bytes;
        if (sscanf(line, "%255[^,],%255[^,],%d,%d", src, dst, &ts, &bytes) == 4) {
            double score = (bytes % 1000) * 1.5;
            printf("%s,%s,%.1f\n", src, dst, score);
        }
    }
    return 0;
}
EOF

    gcc -O3 -s /app/net_scorer.c -o /app/net_scorer
    rm /app/net_scorer.c

    # Create baseline_etl.sh
    cat << 'EOF' > /home/user/baseline_etl.sh
#!/bin/bash
cat /home/user/data/raw_edges.csv | while IFS=, read -r src dst ts bytes; do
    if [ "$bytes" -ge 100 ]; then
        echo "$src,$dst,$ts,$bytes" | /app/net_scorer >> /home/user/scores.txt
    fi
done
EOF
    chmod +x /home/user/baseline_etl.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
