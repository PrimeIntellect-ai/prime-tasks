#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip bc gawk
pip3 install pytest

mkdir -p /home/user
cd /home/user

cat << 'EOF' > users.csv
user_id,country,signup_date
EOF

cat << 'EOF' > impressions.csv
user_id,variant
EOF

cat << 'EOF' > clicks.csv
user_id,timestamp
EOF

for i in $(seq 1000 2999); do
    mod1=$(($i % 10))
    mod2=$(($i % 7))
    mod3=$(($i % 13))

    if [ $mod1 -le 5 ]; then
        country="US"
    elif [ $mod1 -le 7 ]; then
        country="UK"
    else
        country="CA"
    fi
    echo "$i,$country,2023-01-01" >> /home/user/users.csv

    if [ $(($i % 2)) -eq 0 ]; then
        variant="A"
    else
        variant="B"
    fi
    echo "$i,$variant" >> /home/user/impressions.csv

    is_click=0
    if [ "$country" = "US" ]; then
        if [ "$variant" = "A" ] && [ $mod3 -le 1 ]; then
            is_click=1
        elif [ "$variant" = "B" ] && [ $mod2 -le 1 ]; then
            is_click=1
        fi
    fi

    if [ $is_click -eq 1 ]; then
        echo "$i,2023-01-02" >> /home/user/clicks.csv
    fi
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
