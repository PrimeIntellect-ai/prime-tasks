#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/log_pipeline/inputs

    # Create input logs using seq to ensure compatibility with /bin/sh
    for i in $(seq 1 15); do
        echo "data $i" > /home/user/log_pipeline/inputs/app$i.log
    done

    cat << 'EOF' > /home/user/log_pipeline/merge_logs.sh
#!/bin/bash
f1=$1
f2=$2

# Pre-processing simulation
sleep 0.1

exec 3> "$f1.lock"
flock 3
# Sleep to force the deadlock consistently when conflicting lock orders exist
sleep 0.2
exec 4> "$f2.lock"
flock 4

# Merge operation
cat "$f2" >> "$f1"
echo "merged" > "$f2"

# Unlock
flock -u 4
flock -u 3
EOF
    chmod +x /home/user/log_pipeline/merge_logs.sh

    cat << 'EOF' > /home/user/log_pipeline/run_all.sh
#!/bin/bash
while read -r f1 f2; do
    ./merge_logs.sh "$f1" "$f2" &
done < jobs.txt
wait
echo "All jobs finished successfully" > success.log
EOF
    chmod +x /home/user/log_pipeline/run_all.sh

    cat << 'EOF' > /home/user/log_pipeline/jobs.txt
inputs/app1.log inputs/app3.log
inputs/app4.log inputs/app5.log
inputs/app10.log inputs/app11.log
inputs/app2.log inputs/app6.log
inputs/app6.log inputs/app2.log
inputs/app8.log inputs/app9.log
EOF

    chmod -R 777 /home/user
