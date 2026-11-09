#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    apt-get install -y hdf5-tools netcat-openbsd bc jq python3-h5py

    mkdir -p /app/ml-server-0.8.2
    mkdir -p /home/user
    cd /home/user

    # Generate test HDF5 file
    python3 -c "
import h5py, numpy as np
with h5py.File('raw_input.h5', 'w') as f:
    f.create_dataset('/data/batch_1', data=np.linspace(0.1, 10.0, 100, dtype=np.float64))
"

    # Create broken vendored package
    cat << 'EOF' > /app/ml-server-0.8.2/compute_norm.sh
#!/bin/bash
H5_FILE=$1
# Extract first 100 values
h5dump -y -d /data/batch_1 $H5_FILE | grep -v "{" | grep -v "}" | grep -v "DATASPACE" | grep -v "DATA" | tr -d ',' > /tmp/raw_vals.txt

rm -f /tmp/sums.txt
# Deliberate race condition / unordered reduction
for i in {0..9}; do
    (
        start=$((i*10 + 1))
        end=$((start+9))
        sed -n "${start},${end}p" /tmp/raw_vals.txt | awk '{s+=$1} END {print s}' >> /tmp/sums.txt
    ) &
done
wait

# Non-deterministic total sum
TOTAL_SUM=$(awk '{s+=$1} END {printf "%.6f", s}' /tmp/sums.txt)
SCALE=$(echo "scale=6; 1.0 / $TOTAL_SUM" | bc)
PREVIEW=$(head -n 3 /tmp/raw_vals.txt | awk -v s="$SCALE" '{printf "%.6f ", $1 * s}')
echo "{\"scale_factor\": $SCALE, \"normalized_preview\": [$(echo $PREVIEW | awk '{print $1", "$2", "$3}')]}"
EOF
    chmod +x /app/ml-server-0.8.2/compute_norm.sh

    cat << 'EOF' > /app/ml-server-0.8.2/serve.sh
#!/bin/bash
PORT=8080
echo "Starting server on $PORT"
while true; do
    # Broken server logic: missing response headers, incorrect auth check
    nc -l -p $PORT -q 1 -e bash -c '
        read req
        read auth_header
        if echo "$auth_header" | grep -q "X-Auth: secret-token-123"; then
            PAYLOAD=$(/app/ml-server-0.8.2/compute_norm.sh /home/user/raw_input.h5)
            echo "HTTP/1.1 200 OK"
            echo "Content-Type: application/json"
            echo ""
            echo "$PAYLOAD"
        else
            echo "HTTP/1.1 403 Forbidden"
            echo ""
        fi
    '
done
EOF
    chmod +x /app/ml-server-0.8.2/serve.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
