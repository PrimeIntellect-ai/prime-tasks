#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk coreutils grep sed
    pip3 install pytest

    # Create user
    useradd -m -s /bin/bash user || true

    # Create app dir and compile anomaly_scorer
    mkdir -p /app
    cat << 'EOF' > /app/anomaly_scorer.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[65536];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\r\n")] = 0;
        char *tab = strchr(line, '\t');
        if (!tab) continue;
        *tab = '\0';
        char *userid = line;
        char *actions = tab + 1;

        float score = 0.0;
        int len = strlen(actions);
        score += len * 0.01;

        if (strstr(actions, "FAIL,FAIL,FAIL,LOGIN")) score += 50.0;
        if (strstr(actions, "VIEW,BUY,REFUND,BUY")) score += 30.0;

        unsigned int hash = 0;
        for (int i=0; userid[i]; i++) hash = hash * 31 + userid[i];
        score += (hash % 1000) / 1000.0;

        printf("%s\t%.4f\n", userid, score);
    }
    return 0;
}
EOF
    gcc -O3 /app/anomaly_scorer.c -o /app/anomaly_scorer
    strip /app/anomaly_scorer
    rm /app/anomaly_scorer.c

    # Generate raw logs
    cat << 'EOF' > /tmp/generate_logs.py
import random
from datetime import datetime, timedelta

actions = ["LOGIN", "VIEW", "BUY", "LOGOUT", "FAIL", "REFUND", "DEBUG_PING", "DEBUG_TRACE"]
start_time = datetime(2023, 10, 1)

# Using a fixed seed to ensure reproducibility
random.seed(42)

with open("/home/user/raw_logs.txt", "w") as f:
    for i in range(2000000):
        uid = f"U{random.randint(1000, 9999)}"
        act = random.choice(actions)
        if uid.startswith("U99"):
            if random.random() < 0.1: act = "FAIL"
        ts = start_time + timedelta(seconds=random.randint(0, 86400 * 30))
        f.write(f"{ts.strftime('%Y-%m-%d %H:%M:%S')}|{uid}|{act}|1.2.3.4\n")
EOF
    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py

    # Generate truth
    cat << 'EOF' > /tmp/generate_truth.sh
#!/bin/bash
grep -v "|DEBUG_" /home/user/raw_logs.txt | \
sort -t'|' -k2,2 -k1,1 | \
awk -F'|' '
  BEGIN { OFS="\t" }
  {
    if ($2 != last_user) {
      if (last_user != "") {
        print last_user, acts
      }
      last_user = $2
      last_act = $3
      acts = $3
    } else {
      if ($3 != last_act) {
        acts = acts "," $3
        last_act = $3
      }
    }
  }
  END {
    if (last_user != "") print last_user, acts
  }
' | /app/anomaly_scorer | sort -k2,2nr -k1,1 | head -n 100 | tr '\t' ',' > /tmp/truth_top_100_anomalies.csv
EOF
    bash /tmp/generate_truth.sh
    rm /tmp/generate_truth.sh

    chmod -R 777 /home/user
    chmod 777 /tmp/truth_top_100_anomalies.csv
