#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/server_logs.txt
2023-10-10 08:15:00 [INFO] ResponseTime: 120
2023-10-10 09:20:00 [INFO] ResponseTime: 140
2023-10-10 14:00:00 [INFO] ResponseTime: 50
2023-10-10 21:30:00 [INFO] ResponseTime: 100
2023-10-10 22:10:00 [INFO] ResponseTime: 200
2023-10-10 22:45:00 [INFO] ResponseTime: 300
2023-10-10 23:05:00 [INFO] ResponseTime: 150
EOF

cat << 'EOF' > /home/user/aggregate_logs.sh
#!/bin/bash
TZ_OFFSET=3
declare -a sum_rt
declare -a count_rt

for i in {0..23}; do
    sum_rt[$i]=0
    count_rt[$i]=0
done

while read -r date time level label rt; do
    # Extract hour
    HH=${time%%:*}

    # Bug 1: Base-8 evaluation error for '08' and '09'
    # Bug 2: No modulo 24 for day rollover
    adj_hour=$((HH + TZ_OFFSET))

    # Assertion to ensure valid hour
    if [ "$adj_hour" -ge 24 ] || [ "$adj_hour" -lt 0 ]; then
        echo "Assertion failed: adjusted hour $adj_hour is invalid for time $time" >&2
        exit 1
    fi

    sum_rt[$adj_hour]=$((sum_rt[$adj_hour] + rt))
    count_rt[$adj_hour]=$((count_rt[$adj_hour] + 1))
done < /home/user/server_logs.txt

rm -f /home/user/hourly_averages.txt
for i in {0..23}; do
    if [ "${count_rt[$i]}" -gt 0 ]; then
        avg=$((sum_rt[$i] / count_rt[$i]))
        printf "Hour: %02d, Avg: %d\n" "$i" "$avg" >> /home/user/hourly_averages.txt
    fi
done
EOF

chmod +x /home/user/aggregate_logs.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
