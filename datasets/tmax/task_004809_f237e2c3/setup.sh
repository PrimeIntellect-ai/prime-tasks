#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    mkdir -p /home/user/project

    cat << 'EOF' > /home/user/project/sensor_data.txt
12.5
15.0
ERR_TIMEOUT
18.5
CORRUPT_DATA
14.0
EOF

    cat << 'EOF' > /home/user/project/build_model.sh
#!/bin/bash

# Read sensor data
SUM=0
COUNT=0
while read -r line; do
    SUM=$((SUM + line))
    COUNT=$((COUNT + 1))
done < /home/user/project/sensor_data.txt

AVERAGE=$((SUM / COUNT))

BASELINE=0
ITERATION=1
DIFF=100

while [ $(echo "$DIFF >= 0.01" | bc) -eq 1 ]; do
    OLD_BASELINE=$BASELINE
    # Update baseline
    BASELINE=$(( (BASELINE + AVERAGE) / 2 ))

    # Calculate difference
    DIFF=$(echo "$BASELINE - $OLD_BASELINE" | bc)
    DIFF=${DIFF#-} # absolute value
    ITERATION=$((ITERATION + 1))

    # Infinite loop protection
    if [ $ITERATION -gt 100 ]; then
        echo "Convergence failure!"
        exit 1
    fi
done

echo $BASELINE > /home/user/project/final_output.txt
EOF

    chmod +x /home/user/project/build_model.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
