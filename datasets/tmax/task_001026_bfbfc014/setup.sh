#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc
    pip3 install pytest pandas numpy

    mkdir -p /data
    cat << 'EOF' > /data/network_logs.txt
Source: 1
Target: 2
Weight: 1.0
---
Source: 2
Target: 3
Weight: 1.0
---
Source: 3
Target: 1
Weight: 1.0
---
Source: 4
Target: 3
Weight: 1.0
EOF

    mkdir -p /app/pagerank-awk-1.0
    cat << 'EOF' > /app/pagerank-awk-1.0/run_pagerank.sh
#!/bin/bash
awk -f /app/pagerank-awk-1.0/pr.awk $1
EOF
    chmod +x /app/pagerank-awk-1.0/run_pagerank.sh

    cat << 'EOF' > /app/pagerank-awk-1.0/pr.awk
BEGIN { FS=","; d=0.85; max_iter=50; tol=1e-6 }
NR>1 {
    nodes[$1]=1; nodes[$2]=1;
    out_degree[$1]+=$3;
    edge[$1,$2]=$3;
}
END {
    N=0; for (i in nodes) N++;
    for (i in nodes) pr[i] = 1.0 / N;

    for (iter=1; iter<=max_iter; iter++) {
        diff=0;
        base = 1 - d; # BUG: should be (1 - d) / N
        for (i in nodes) new_pr[i] = base;

        for (i in nodes) {
            if (out_degree[i] > 0) {
                for (j in nodes) {
                    if ((i,j) in edge) {
                        new_pr[j] += d * pr[i] * (edge[i,j] / out_degree[i]);
                    }
                }
            } else {
                for (j in nodes) new_pr[j] += d * pr[i] / N;
            }
        }
        for (i in nodes) {
            diff += (new_pr[i] - pr[i])^2;
            pr[i] = new_pr[i];
        }
        if (diff < tol) break;
    }
    for (i in nodes) print i "," pr[i];
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
