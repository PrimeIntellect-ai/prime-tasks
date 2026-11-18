#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip zstd bc tar gawk sed grep coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/setup.sh
#!/bin/bash
echo "ID,SensorA,SensorB,SensorC" > /home/user/raw_data.csv
for i in $(seq 1 1000); do
    id=$((9000000000000000000 + i))

    if (( i % 10 == 0 )); then
        sa="NaN"
    else
        sa="1.$i"
    fi

    sb="NaN"
    sc="2.$i"

    echo "$id,$sa,$sb,$sc" >> /home/user/raw_data.csv
done
EOF

/bin/bash /home/user/setup.sh
rm /home/user/setup.sh

chmod -R 777 /home/user
