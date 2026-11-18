#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app
    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/app/raw_data.csv
id,timestamp,value,status
1,2023-10-01,100,OK
2,2023-10-01,200,OK
3,2023-10-01,15.5,ERROR
4,2023-10-01,300,OK
5,2023-10-01,-50,OK
6,2023-10-01,400,OK
7,2023-10-01,50a,OK
8,2023-10-01,500,OK
EOF

    cat << 'EOF' > /home/user/app/service_a.sh
#!/bin/bash
PIPE="/tmp/data_pipe"
if [[ ! -p $PIPE ]]; then
    mkfifo $PIPE
fi

exec 3> "$PIPE"

tail -n +2 /home/user/app/raw_data.csv | while IFS=',' read -r id ts val status; do
    # BUGGY VALIDATION: only checks if it contains letters
    if [[ "$val" == *[a-zA-Z]* ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Skipping invalid value for ID $id" >> /home/user/logs/service_a.log
        continue
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Sending ID $id" >> /home/user/logs/service_a.log
    echo "$id,$val" >&3
    sleep 0.1
done

echo "EOF" >&3
exec 3>&-
EOF

    cat << 'EOF' > /home/user/app/service_b.sh
#!/bin/bash
PIPE="/tmp/data_pipe"
total=0

while read -r line; do
    if [[ "$line" == "EOF" ]]; then break; fi
    id=$(echo "$line" | cut -d',' -f1)
    val=$(echo "$line" | cut -d',' -f2)

    echo "$(date +%s) - Received ID $id" >> /home/user/logs/service_b.log

    # Simulate crash on non-positive integer
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [ "$val" -le 0 ]; then
        echo "$(date +%s) - FATAL ERROR: Invalid arithmetic operation on $val for ID $id" >> /home/user/logs/service_b.log
        exit 1
    fi

    total=$((total + val))
    echo "$(date +%s) - Processed ID $id, Current Total: $total" >> /home/user/logs/service_b.log
done < "$PIPE"

echo "Final Total: $total" > /home/user/app/final_output.txt
EOF

    cat << 'EOF' > /home/user/app/run_pipeline.sh
#!/bin/bash
mkdir -p /home/user/logs
rm -f /home/user/logs/*
rm -f /tmp/data_pipe
/home/user/app/service_b.sh &
PID_B=$!
/home/user/app/service_a.sh
wait $PID_B
EOF

    chmod +x /home/user/app/*.sh

    cat << 'EOF' > /home/user/logs/service_a.log
2023-10-25 10:00:01 - Sending ID 1
2023-10-25 10:00:02 - Sending ID 2
2023-10-25 10:00:03 - Sending ID 3
2023-10-25 10:00:04 - Sending ID 4
2023-10-25 10:00:05 - Sending ID 5
2023-10-25 10:00:06 - Sending ID 6
2023-10-25 10:00:07 - Skipping invalid value for ID 7
2023-10-25 10:00:08 - Sending ID 8
EOF

    cat << 'EOF' > /home/user/logs/service_b.log
1698228001 - Received ID 1
1698228001 - Processed ID 1, Current Total: 100
1698228002 - Received ID 2
1698228002 - Processed ID 2, Current Total: 300
1698228003 - Received ID 3
1698228003 - FATAL ERROR: Invalid arithmetic operation on 15.5 for ID 3
EOF

    chmod -R 777 /home/user
