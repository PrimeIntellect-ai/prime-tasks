#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip bc gawk
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/generate_reads.py
import random

random.seed(42)
with open('/home/user/spatial_reads.csv', 'w') as f:
    for _ in range(20000):
        x = round(random.uniform(0.0, 100.0), 2)
        y = round(random.uniform(0.0, 100.0), 2)
        # Generate a random 50-mer
        seq = "".join(random.choices(['A', 'C', 'G', 'T'], k=50))
        # Inject the primer 'GATTACA' with ~5% probability
        if random.random() < 0.05:
            insert_pos = random.randint(0, 43)
            seq = seq[:insert_pos] + "GATTACA" + seq[insert_pos+7:]
        f.write(f"{x},{y},{seq}\n")
EOF
python3 /tmp/generate_reads.py

cat << 'EOF' > /home/user/mcmc_sampler.sh
#!/bin/bash
if [ -z "$1" ]; then
    echo "Error: missing count argument"
    exit 1
fi
COUNT=$1
# Mock MCMC posterior mean calculation
POSTERIOR=$(echo "scale=4; $COUNT * 1.374 + 15.2" | bc)
echo "MCMC Posterior Mean: $POSTERIOR"
EOF

chmod +x /home/user/mcmc_sampler.sh
chmod -R 777 /home/user
