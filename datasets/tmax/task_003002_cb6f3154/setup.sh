#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user/data

    # Generate 100 dummy "ODE trajectory" files
    for i in $(seq 1 100); do
        val=$(awk -v i="$i" 'BEGIN { print sin(i) * 10 + 20 }')
        echo "0.0 0.0" > /home/user/data/traj_${i}.dat
        echo "1.0 $val" >> /home/user/data/traj_${i}.dat
    done

    cat << 'EOF' > /home/user/build_dataset.sh
#!/bin/bash
export LC_ALL=C
rm -f /home/user/singular_values.txt

# Extract values in parallel
ls /home/user/data/traj_*.dat | xargs -n 1 -P 4 -I {} bash -c '
    val=$(tail -n 1 {} | awk "{print \$2 * 0.987}")
    echo "$val" >> /home/user/singular_values.txt
'

# Calculate distance (non-reproducible due to random order!)
awk '{ dist += ($1 - (NR*0.5))^2 } END { printf "%.6f\n", dist }' /home/user/singular_values.txt > /home/user/training_label.txt
EOF

    chmod +x /home/user/build_dataset.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
