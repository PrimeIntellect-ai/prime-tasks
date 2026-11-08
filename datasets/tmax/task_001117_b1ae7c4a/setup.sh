#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 bc gawk
    pip3 install pytest

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/job_12.log
[INFO] Starting job_12
[INFO] Processing data...
[INFO] Convergence achieved in 45 iterations.
[INFO] SUCCESS
EOF

    cat << 'EOF' > /home/user/logs/job_773.log
[INFO] Starting job_773
[INFO] Processing data...
[WARN] Iteration count exceeded safe limits.
[ERROR] Container TIMEOUT - KILLED
EOF

    cat << 'EOF' > /home/user/logs/job_800.log
[INFO] Starting job_800
[INFO] Processing data...
[INFO] Convergence achieved in 12 iterations.
[INFO] SUCCESS
EOF

    sqlite3 /home/user/jobs.db << 'EOF'
CREATE TABLE jobs(job_name TEXT, init_x REAL, learning_rate REAL);
INSERT INTO jobs VALUES ('job_12', 10.0, 0.1);
INSERT INTO jobs VALUES ('job_773', 0.0, 1.0);
INSERT INTO jobs VALUES ('job_800', 5.0, 0.05);
EOF

    cat << 'EOF' > /home/user/gd_optimizer.sh
#!/bin/bash
# Gradient descent for f(x) = x^2 - 4x + 4
# Minimum is at x = 2

x=$1
lr=$2
threshold=0.0001
diff=100

while [ $(echo "$diff > $threshold" | bc -l) -eq 1 ]; do
    # Gradient of x^2 - 4x + 4 is 2x - 4
    grad=$(echo "2 * $x - 4" | bc -l)
    new_x=$(echo "$x - $lr * $grad" | bc -l)

    # Absolute difference
    diff=$(echo "$new_x - $x" | bc -l | awk '{print ($1<0?-$1:$1)}')

    x=$new_x
done

echo $x
EOF

    chmod +x /home/user/gd_optimizer.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
