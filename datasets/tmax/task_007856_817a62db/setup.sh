#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc gawk
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/calc_variance.sh
#!/bin/bash
input_file=$1
target_sensor=$2

sum=0
sum_sq=0
count=0

while IFS=',' read -r ts sensor val; do
    if [ "$sensor" = "$target_sensor" ]; then
        sum=$((sum + val))
        sum_sq=$((sum_sq + val * val))
        count=$((count + 1))
    fi
done < "$input_file"

if [ $count -gt 0 ]; then
    mean=$((sum / count))
    variance=$(( (sum_sq - (sum * sum) / count) / count ))
    echo $variance
else
    echo 0
fi
EOF
    chmod +x /home/user/calc_variance.sh

    python3 -c "
import random
random.seed(42)
with open('/home/user/daily_query.csv', 'w') as f:
    for i in range(1, 5001):
        if i == 3421:
            # Buggy line (empty value)
            f.write(f'2023-10-12T10:00:00Z,SENSOR_X,\n')
        else:
            # Base value 2,000,000 + random variation up to 5000
            val = 2000000 + random.randint(0, 5000)
            f.write(f'2023-10-12T10:00:00Z,SENSOR_X,{val}\n')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
