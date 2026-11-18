#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc
    pip3 install pytest

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    # Create data.csv
    cat << 'EOF' > data.csv
id,value
1,10.1234
2,20.5678
3,30.9012
4,40.3456
5,50.7890
EOF

    # Create the dummy shared library and binary
    cat << 'EOF' > custom_math.c
double add(double a, double b) { return a + b; }
EOF
    gcc -shared -fPIC -o libcustom_math.so custom_math.c

    cat << 'EOF' > metric_parser.c
#include <stdio.h>
extern double add(double a, double b);
int main() {
    printf("Parser Ready\n");
    return 0;
}
EOF
    gcc -o metric_parser metric_parser.c -L. -lcustom_math

    # Create the buggy bash script
    cat << 'EOF' > aggregate_metrics.sh
#!/bin/bash

# Attempt to run parser
./metric_parser > /dev/null

# Simulate long running background tasks
sleep 100 &
sleep 100 &

# Calculate average of column 2
sum=0
count=0
tail -n +2 data.csv | while IFS=',' read -r id val; do
    sum=$(echo "$sum + $val" | bc)
    count=$((count + 1))
done

# This loses precision
avg=$(echo "$sum / $count" | bc)

echo "$avg" > /home/user/pipeline/result.txt

wait
EOF
    chmod +x aggregate_metrics.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
