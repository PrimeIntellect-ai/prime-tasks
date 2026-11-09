#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tzdata
    pip3 install pytest

    mkdir -p /home/user/log_processor/logs
    mkdir -p /home/user/log_processor/out

    # Create buggy script
    cat << 'EOF' > /home/user/log_processor/process_logs.sh
#!/bin/bash
mkdir -p out
> out/tmp.log

for f in logs/*.log; do
    (
        while read -r line; do
            ts=$(echo "$line" | cut -d' ' -f1,2)
            msg=$(echo "$line" | cut -d' ' -f3-)
            epoch=$(date -d "$ts" +%s)
            echo "$epoch $msg" >> out/tmp.log
        done < "$f"
    ) &
done
wait

sort -n out/tmp.log > out/final.log
EOF
    chmod +x /home/user/log_processor/process_logs.sh

    # Create logs with null bytes and varying timezones using printf to ensure correct null byte insertion
    # us-east log (America/New_York)
    printf "2023-10-01 08:00:00 \000Message 1 from US\n" > /home/user/log_processor/logs/us-east_1.log
    printf "2023-10-01 08:05:00 Message 2 from \000US\n" >> /home/user/log_processor/logs/us-east_1.log

    # eu-west log (Europe/London) - 08:00 in NY is 13:00 in London
    printf "2023-10-01 12:55:00 Message 1 from EU\n" > /home/user/log_processor/logs/eu-west_1.log
    printf "2023-10-01 13:02:00 Message 2 \000from EU\n" >> /home/user/log_processor/logs/eu-west_1.log

    # asia log (Asia/Tokyo) - 08:00 in NY is 21:00 in Tokyo
    printf "2023-10-01 20:50:00 \000Message 1 from Asia\n" > /home/user/log_processor/logs/asia_1.log
    printf "2023-10-01 21:10:00 Message 2 from Asia\n" >> /home/user/log_processor/logs/asia_1.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
