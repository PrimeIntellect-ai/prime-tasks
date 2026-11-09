#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Let's write a python script to generate randoms.txt and calculate the exact truth
    python3 -c "
import random
random.seed(42)
L = 1000
GC = 520
with open('/home/user/randoms.txt', 'w') as f:
    for _ in range(50000):
        f.write(str(random.randint(0, 32767)) + '\n')

with open('/home/user/seq.fasta', 'w') as f:
    f.write('>seq1\n')
    seq = 'G' * GC + 'A' * (L - GC)
    # shuffle
    seq_list = list(seq)
    random.shuffle(seq_list)
    f.write(''.join(seq_list) + '\n')
"

    # Ground truth calculation:
    python3 -c "
with open('/home/user/randoms.txt') as f:
    randoms = [int(line.strip()) for line in f]
L = 1000
GC = 520
X = 0
for R in randoms:
    if R * L < GC * 32767:
        X += 1
    else:
        X -= 1
with open('/home/user/expected_result.txt', 'w') as f:
    f.write(str(X) + '\n')
"

    # Create slow_mcmc.sh
    cat << 'EOF' > /home/user/slow_mcmc.sh
#!/bin/bash
seq=$(grep -v '^>' /home/user/seq.fasta | tr -d '\n')
len=${#seq}
gc=$(echo "$seq" | tr -cd 'GC' | wc -c)
p=$(echo "scale=5; $gc / $len" | bc)

x=0
while read r; do
    is_less=$(echo "$r / 32767 < $p" | bc -l)
    if [ "$is_less" -eq 1 ]; then
        x=$((x+1))
    else
        x=$((x-1))
    fi
done < /home/user/randoms.txt

echo $x
EOF
    chmod +x /home/user/slow_mcmc.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
