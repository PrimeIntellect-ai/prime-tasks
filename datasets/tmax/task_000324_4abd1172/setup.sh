#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    mkdir -p /home/user/telemetry
    cd /home/user/telemetry

    # Create initial state
    cat << 'EOF' > initial_state.csv
S1,10.0000
S2,20.0000
EOF

    # Create initial broken state just to simulate the crash
    cp initial_state.csv current_state.csv

    # Create WAL
    cat << 'EOF' > sensor.wal
1,S1,12.0000
2,S2,18.0000
3,S1,15.0000
4,S2,ERROR_NULL
5,S1,11.0000
6,S2,22.0000
EOF

    # Create the buggy script
    cat << 'EOF' > process_wal.sh
#!/bin/bash
cp initial_state.csv current_state.csv

while IFS=',' read -r seq sensor val; do
    if [[ -z "$seq" ]]; then continue; fi

    curr_val=$(grep "^$sensor," current_state.csv | cut -d',' -f2)

    # BUG 1: bc without scale causes truncation
    # BUG 2: no check for numeric $val, bc will throw error on ERROR_NULL and script fails to produce expected output
    new_val=$(echo "($curr_val * 0.9) + ($val * 0.1)" | bc)

    # Format the output just to be safe (but new_val is already truncated)
    formatted_val=$(printf "%.4f" "$new_val")

    # Update state
    sed -i "s/^$sensor,.*/$sensor,$formatted_val/" current_state.csv

done < sensor.wal
EOF

    chmod +x process_wal.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
