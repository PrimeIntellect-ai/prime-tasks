#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg gawk bc
    pip3 install pytest

    mkdir -p /app

    # Generate dummy sensor video
    ffmpeg -f lavfi -i "testsrc=duration=30:size=200x200:rate=1" -c:v libx264 /app/sensor_feed.mp4

    # Create oracle script
    cat << 'EOF' > /app/oracle_calc_cov.sh
#!/bin/bash
# /app/oracle_calc_cov.sh
total=$#
n=$((total / 2))
sum_a=0
sum_b=0

for ((i=1; i<=n; i++)); do
    sum_a=$((sum_a + ${!i}))
done

for ((i=n+1; i<=total; i++)); do
    sum_b=$((sum_b + ${!i}))
done

mean_a_sum=$sum_a
mean_b_sum=$sum_b

# Compute covariance
awk -v n="$n" -v args="$*" '
BEGIN {
    split(args, arr, " ")
    sum_a = 0
    sum_b = 0
    for(i=1; i<=n; i++) { sum_a += arr[i] }
    for(i=n+1; i<=2*n; i++) { sum_b += arr[i] }
    mean_a = sum_a / n
    mean_b = sum_b / n

    cov_sum = 0
    for(i=1; i<=n; i++) {
        cov_sum += (arr[i] - mean_a) * (arr[i+n] - mean_b)
    }
    cov = cov_sum / (n - 1)
    res = int(cov * 1000)
    print res
}'
EOF
    chmod +x /app/oracle_calc_cov.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
