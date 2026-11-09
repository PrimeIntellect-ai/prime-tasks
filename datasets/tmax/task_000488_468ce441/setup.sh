#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gawk binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/perf_task/logs
    cd /home/user/perf_task

    # 1. Create legacy_bin (computes the Nth triangular number: N*(N+1)/2)
    cat << 'EOF' > legacy.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    uint64_t n = strtoull(argv[1], NULL, 10);
    uint64_t res = n * (n + 1) / 2;
    printf("%llu\n", (unsigned long long)res);
    return 0;
}
EOF
    gcc -O3 legacy.c -o legacy_bin
    strip legacy_bin
    rm legacy.c

    # 2. Create slow_processor.c
    cat << 'EOF' > slow_processor.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// BUGGY AND SLOW FORMULA IMPLEMENTATION
uint64_t compute_metric(uint32_t n) {
    uint64_t sum = 0;
    for (uint32_t i = 1; i <= n; i++) {
        sum += i;
    }
    return sum;
}

int main() {
    char line[256];
    char date[32], time[32], service[32];
    uint32_t val; // Bug: should be uint64_t to match large inputs

    while (fgets(line, sizeof(line), stdin)) {
        if (sscanf(line, "%s %s [%[^]]] val=%u", date, time, service, &val) == 4) {
            uint64_t metric = compute_metric(val);
            printf("%s %s | %s | %u | %llu\n", date, time, service, val, (unsigned long long)metric);
        }
    }
    return 0;
}
EOF

    # 3. Create fuzz_test.sh
    cat << 'EOF' > fuzz_test.sh
#!/bin/bash
TARGET=$1
if [ -z "$TARGET" ]; then echo "Usage: $0 <binary>"; exit 1; fi

for i in {1..20}; do
    # Generate random number up to 4 billion
    VAL=$(( RANDOM * RANDOM * RANDOM % 4000000000 ))
    EXPECTED=$(./legacy_bin $VAL)

    # Create a dummy log line
    ACTUAL=$(echo "2023-01-01 12:00:00 [test] val=$VAL" | $TARGET | awk -F' \\| ' '{print $4}')

    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "Fuzz failed on input $VAL: expected $EXPECTED, got $ACTUAL"
        exit 1
    fi
done
echo "Fuzz testing passed!"
EOF
    chmod +x fuzz_test.sh

    # 4. Create log files
    cat << 'EOF' > logs/svcA.log
2023-10-01 10:05:00 [svcA] val=1000000
2023-10-01 10:15:00 [svcA] val=3000000000
EOF

    cat << 'EOF' > logs/svcB.log
2023-10-01 10:00:00 [svcB] val=5000
2023-10-01 10:10:00 [svcB] val=4000000000
EOF

    cat << 'EOF' > logs/svcC.log
2023-10-01 10:02:00 [svcC] val=2000000
2023-10-01 10:12:00 [svcC] val=0
EOF

    chmod -R 777 /home/user
