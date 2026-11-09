#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data/raw_logs/
    mkdir -p /app/bash-ops-etl-0.1.0/bin

    cat << 'EOF' > /app/bash-ops-etl-0.1.0/bin/extract_valid_metrics.sh
#!/bin/bash
# Perturbed script: $3 condition drops zeros
awk -F, 'NR>1 && $2=="SUCCESS" && $3 {print $3}' "$1"
EOF
    chmod +x /app/bash-ops-etl-0.1.0/bin/extract_valid_metrics.sh

    # Generate dummy data
    for i in $(seq 1 50); do
        f="/home/user/data/raw_logs/exp_$(printf "%02d" $i).csv"
        echo "experiment_id,run_status,val_loss" > "$f"
        for j in $(seq 1 20); do
            # Mix of SUCCESS/FAILED, some zeros, some empty
            status="SUCCESS"
            if (( RANDOM % 5 == 0 )); then status="FAILED"; fi

            loss=$(( RANDOM % 10 ))
            if (( loss == 0 )); then
                val_loss="0.0"
            elif (( loss == 1 )); then
                val_loss=""
            else
                val_loss=$(echo "scale=2; $loss / 10.0" | bc)
            fi
            echo "exp_${i}_${j},${status},${val_loss}" >> "$f"
        done
    done

    chown -R user:user /app/bash-ops-etl-0.1.0
    chmod -R 777 /home/user
