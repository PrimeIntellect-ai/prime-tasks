#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /app/embed_oracle.c
#include <stdio.h>
#include <string.h>
#include <math.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    char *text = argv[1];
    int len = strlen(text);
    float v[5] = {0.1, 0.2, 0.3, 0.4, 0.5};
    for(int i=0; i<len; i++) {
        v[i%5] += (float)(text[i]) * 0.01;
    }
    float norm = 0;
    for(int i=0; i<5; i++) norm += v[i]*v[i];
    norm = sqrt(norm);
    for(int i=0; i<5; i++) {
        printf("%f ", v[i]/norm);
    }
    printf("\n");
    return 0;
}
EOF
gcc -O3 -s /app/embed_oracle.c -o /app/embed_oracle -lm
rm /app/embed_oracle.c

mkdir -p /home/user
cat << 'EOF' > /home/user/items.csv
item_id,item_text
i1,apple pie recipe
i2,banana bread easy
i3,chocolate cake
i4,data science guide
i5,machine learning tutorial
EOF

cat << 'EOF' > /home/user/history.csv
user_id,item_id,clicks,impressions
u1,i1,5,10
u1,i2,2,20
u2,i4,10,12
u2,i5,8,10
u3,i3,0,5
EOF

cat << 'EOF' > /home/user/queries.csv
user_id,target_item_id
u1,i3
u2,i1
u3,i4
u4,i5
EOF

# Generate reference solution
python3 -c '
import csv, subprocess, math

# 1. Embeddings
embeddings = {}
with open("/home/user/items.csv") as f:
    next(f)
    for line in f:
        iid, text = line.strip().split(",")
        out = subprocess.check_output(["/app/embed_oracle", text]).decode().strip()
        embeddings[iid] = [float(x) for x in out.split()]

# 2. History & Bayesian CTR
history = {}
tot_clicks = 0
tot_impressions = 0
with open("/home/user/history.csv") as f:
    next(f)
    for line in f:
        u, i, c, imp = line.strip().split(",")
        c, imp = int(c), int(imp)
        tot_clicks += c
        tot_impressions += imp
        if u not in history: history[u] = []
        history[u].append({"item": i, "c": c, "imp": imp})

alpha = tot_clicks
beta = tot_impressions - tot_clicks
global_mean = alpha / (alpha + beta)

for u in history:
    for rec in history[u]:
        rec["smoothed_ctr"] = (rec["c"] + alpha) / (rec["imp"] + alpha + beta)

# 3. Queries
def cos_sim(v1, v2):
    dot = sum(a*b for a,b in zip(v1,v2))
    n1 = math.sqrt(sum(a*a for a in v1))
    n2 = math.sqrt(sum(a*a for a in v2))
    return dot / (n1*n2)

with open("/home/user/truth_predictions.csv", "w") as fout:
    writer = csv.writer(fout)
    writer.writerow(["user_id", "target_item_id", "predicted_ctr"])
    with open("/home/user/queries.csv") as f:
        next(f)
        for line in f:
            u, t = line.strip().split(",")
            if u not in history:
                pred = global_mean
            else:
                num, den = 0.0, 0.0
                t_emb = embeddings[t]
                for rec in history[u]:
                    sim = cos_sim(t_emb, embeddings[rec["item"]])
                    w = max(0, sim)
                    num += w * rec["smoothed_ctr"]
                    den += w
                if den == 0:
                    pred = global_mean
                else:
                    pred = num / den
            writer.writerow([u, t, f"{pred:.6f}"])
'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
