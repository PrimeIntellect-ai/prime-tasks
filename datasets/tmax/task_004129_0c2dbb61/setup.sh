#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip zip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.sh
#!/bin/bash
mkdir -p /home/user/sensor_data
mkdir -p /tmp/dataset_gen
cd /tmp/dataset_gen

generate_log() {
    local file=$1
    local lines=$2
    > "$file"
    for ((i=1; i<=lines; i++)); do
        sensor="SENSOR_$((i % 3 + 1))"
        if (( i % 5 == 0 )); then
            status="ERROR"
        elif (( i % 7 == 0 )); then
            status="WARN"
        else
            status="OK"
        fi

        value=$(( (i * 13) % 100 )).$(( i % 10 ))

        if (( i % 2 == 0 )); then
            noise="[ERR_NOISE_$(( (i % 900) + 100 ))]"
            echo "2023-10-01T12:00:00Z | $sensor | $value$noise | $status" >> "$file"
        else
            echo "2023-10-01T12:00:00Z | $sensor | $value | $status" >> "$file"
        fi
    done
}

mkdir group_1
generate_log group_1/data1.log 10000
generate_log group_1/data2.log 15000
zip -r group_1.zip group_1/

mkdir group_2
generate_log group_2/data3.log 20000
zip -r group_2.zip group_2/

tar -cvf master_archive.tar group_1.zip group_2.zip
mv master_archive.tar /home/user/sensor_data/
chown -R user:user /home/user/sensor_data

rm -rf /tmp/dataset_gen
EOF

    bash /tmp/setup.sh
    chmod -R 777 /home/user
