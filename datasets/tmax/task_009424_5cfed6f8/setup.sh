#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk coreutils
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_data.sh
#!/bin/bash
cd /home/user
echo "id,sensor_1,sensor_2,sensor_3,is_anomaly" > sensor_data.csv
for i in $(seq 1 60); do
    s1="10.0"
    s2=$((RANDOM % 100))
    s3=$((i + 9)) # values from 10 to 69
    if [ $s3 -gt 42 ]; then
        anomaly=1
    else
        anomaly=0
    fi
    echo "$i,$s1,$s2,$s3,$anomaly" >> sensor_data.csv
done
EOF
    chmod +x /home/user/setup_data.sh
    /home/user/setup_data.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
