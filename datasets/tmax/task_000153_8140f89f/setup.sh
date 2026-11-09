#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/sensor_stat.c
#include <stdio.h>
#include <stdlib.h>
// BUG: Missing header

int main(int argc, char **argv) {
    if(argc < 3) {
        printf("0.000000\n");
        return 0;
    }
    int n = argc - 1;
    float sum = 0.0f;
    float sum_sq = 0.0f;

    // Single-pass naive algorithm (catastrophic cancellation risk)
    for(int i = 1; i <= n; i++) {
        float val = atof(argv[i]);
        sum += val;
        sum_sq += (val * val);
    }

    float variance = (sum_sq - ((sum * sum) / n)) / (n - 1);
    float stddev = sqrt(variance); // Will cause implicit declaration error

    printf("%f\n", stddev);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/build.sh
#!/bin/bash
# BUG: Missing math library flag
gcc -o /home/user/sensor_stat /home/user/sensor_stat.c
EOF
    chmod +x /home/user/build.sh

    cat << 'EOF' > /home/user/fuzz.sh
#!/bin/bash
rm -f /home/user/fuzz_results.log /home/user/fuzz_status.txt
FAIL=0

for i in {1..50}; do
    # Generate large numbers with small differences
    BASE=$(( 10000000 + RANDOM % 100000 ))
    ARGS=""
    for j in {1..10}; do
        VAL=$(awk -v b="$BASE" -v r="$RANDOM" 'BEGIN { printf "%.2f", b + (r/32767.0) }')
        ARGS="$ARGS $VAL"
    done

    RES=$(/home/user/sensor_stat $ARGS 2>&1)
    echo "Run $i Args: $ARGS -> Result: $RES" >> /home/user/fuzz_results.log

    if [[ "$RES" == *"NaN"* || "$RES" == *"nan"* || "$RES" == *"-nan"* ]]; then
        FAIL=1
    fi
done

if [ $FAIL -eq 0 ]; then
    echo "PASS" > /home/user/fuzz_status.txt
else
    echo "FAIL" > /home/user/fuzz_status.txt
fi
EOF
    chmod +x /home/user/fuzz.sh

    chmod -R 777 /home/user
