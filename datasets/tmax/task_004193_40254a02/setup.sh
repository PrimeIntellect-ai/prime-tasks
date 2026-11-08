#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk tar gzip parallel
    pip3 install pytest

    mkdir -p /app/mcmc-bash-pkg-1.0
    cat << 'EOF' > /app/mcmc-bash-pkg-1.0/mcmc_generator.sh
#!/bin/bash
SEED=$1
N_SAMPLES=$2

rm -f raw_output.txt

# Perturbation: parallel jobs writing to a single file with no locking or sorting
for i in $(seq 1 $N_SAMPLES); do
    (
        # Simulate a pseudo-random MC step
        val=$(awk -v s=$SEED -v i=$i 'BEGIN {srand(s+i); print rand() * 100}')
        echo "$i $val" >> raw_output.txt
    ) &
done
wait

# Bug: raw_output.txt is unsorted, causing non-deterministic EMA
./aggregate.sh raw_output.txt
EOF

    cat << 'EOF' > /app/mcmc-bash-pkg-1.0/aggregate.sh
#!/bin/bash
# Computes an exponential moving average (order dependent)
awk '{
    val=$2; 
    if (ema == "") ema = val; 
    else ema = 0.1 * val + 0.9 * ema;
} END {
    printf "%.6f\n", ema
}' "$1"
EOF

    chmod +x /app/mcmc-bash-pkg-1.0/*.sh
    cd /app && tar -czf mcmc-bash-pkg-1.0.tar.gz mcmc-bash-pkg-1.0
    rm -rf /app/mcmc-bash-pkg-1.0

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace
    chmod -R 777 /home/user
