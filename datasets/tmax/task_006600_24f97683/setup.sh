#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/metrics_service
    cd /home/user/metrics_service

    cat << 'EOF' > fast_stat.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    double val = atof(argv[1]);
    // calculate a fake stat using a math function
    printf("%.4f\n", sqrt(val) * 1.5);
    return 0;
}
EOF

    cat << 'EOF' > metricsd.sh
#!/bin/bash

# Compile helper
gcc fast_stat.c -o fast_stat
if [ $? -ne 0 ]; then
    echo "Failed to compile fast_stat"
    exit 1
fi

processed_tx_ids=()

process_data() {
    local file=$1
    while IFS=, read -r tx_id metric_val extra; do
        if [ -z "$tx_id" ]; then continue; fi

        # Array memory leak here - never truncated
        processed_tx_ids+=("$tx_id")

        # Buggy bc calculation (missing scale)
        stability_score=$(echo "$metric_val / 100.0" | bc)

        result=$(./fast_stat "$stability_score")
        echo "TX:$tx_id RES:$result" >> output.log
    done < "$file"
}

# In production this tails a live file, but for testing we just process one file
process_data "input.csv"
EOF
    chmod +x metricsd.sh

    cat << 'EOF' > test_service.sh
#!/bin/bash
cd /home/user/metrics_service

# 1. Check gcc fix
grep -q "gcc fast_stat.c -lm -o fast_stat" metricsd.sh || grep -q "gcc.*-o fast_stat.*-lm" metricsd.sh
GCC_FIX=$?

# 2. Check bc fix
grep -q "scale=4" metricsd.sh
BC_FIX=$?

# 3. Check memory leak fix (array slicing or unsetting)
grep -q "processed_tx_ids=(" metricsd.sh && grep -Eq "\-100|unset" metricsd.sh
MEM_FIX=$?

if [ $GCC_FIX -eq 0 ] && [ $BC_FIX -eq 0 ] && [ $MEM_FIX -eq 0 ]; then
    echo "SUCCESS: ALL_BUGS_FIXED" > status.log
else
    echo "FAILED" > status.log
fi
EOF
    chmod +x test_service.sh

    cat << 'EOF' > input.csv
1,500,extra
2,600,extra
3,700,extra
EOF

    chmod -R 777 /home/user
