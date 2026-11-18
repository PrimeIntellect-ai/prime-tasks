#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user/sensor_pipeline/input
    mkdir -p /home/user/sensor_pipeline/out

    # Create input data
    for i in $(seq 1 10); do
        echo "1.00$i" > /home/user/sensor_pipeline/input/chunk_$i.dat
        echo "2.00$i" >> /home/user/sensor_pipeline/input/chunk_$i.dat
        echo "3.00$i" >> /home/user/sensor_pipeline/input/chunk_$i.dat
    done

    # Create run_pipeline.sh with race condition
    cat << 'EOF' > /home/user/sensor_pipeline/run_pipeline.sh
#!/bin/bash
rm -f /home/user/sensor_pipeline/out/aggregated.dat
for f in /home/user/sensor_pipeline/input/*.dat; do
    /home/user/sensor_pipeline/process_chunk.sh "$f" &
done
wait
/home/user/sensor_pipeline/calculate_convergence.sh /home/user/sensor_pipeline/out/aggregated.dat
EOF
    chmod +x /home/user/sensor_pipeline/run_pipeline.sh

    # Create process_chunk.sh
    cat << 'EOF' > /home/user/sensor_pipeline/process_chunk.sh
#!/bin/bash
# Simulates processing and writes to shared file without locking
sleep 0.1
cat "$1" >> /home/user/sensor_pipeline/out/aggregated.dat
EOF
    chmod +x /home/user/sensor_pipeline/process_chunk.sh

    # Create calculate_convergence.sh with precision loss
    cat << 'EOF' > /home/user/sensor_pipeline/calculate_convergence.sh
#!/bin/bash
input_file=$1
sum=$(awk '{s+=$1} END {print s}' "$input_file")

# Iterative convergence (bug: no scale set causes precision loss and infinite loop/failure)
val=$sum
prev=0
iterations=0

while [ "$iterations" -lt 50 ]; do
    # BUG: defaults to 0 in bc
    new_val=$(echo "$val / 1.05" | bc)

    diff=$(echo "$val - $new_val" | bc | tr -d '-')
    if [ "$diff" = "0" ]; then
        echo "Converged at $new_val"
        exit 0
    fi
    val=$new_val
    iterations=$((iterations + 1))
done

echo "Error: Failed to converge."
exit 1
EOF
    chmod +x /home/user/sensor_pipeline/calculate_convergence.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
