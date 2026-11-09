#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc bc gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline
    mkdir -p /home/user/logs

    # Create a mock log file for the current UTC date
    CURRENT_DATE=$(date -u +%Y%m%d)
    cat <<EOF > /home/user/logs/app_UTC_${CURRENT_DATE}.log
EVENT_START 1700000000100
EVENT_END 1700000000145
EOF

    # Create the buggy Bash script
    cat <<'EOF' > /home/user/pipeline/aggregate.sh
#!/bin/bash

# Find yesterday's log file (Bug 1: Timezone offset makes it look for the wrong file at 3AM UTC, or we just hardcode the bug to use America/New_York date which might be yesterday)
# To simulate the 3AM UTC page, we force the date calculation with a specific TZ
DATE_STR=$(TZ=America/New_York date -u +%Y%m%d) # Bug: forces wrong date context if relying on local TZ, wait let's make it explicitly look for the current day but with a TZ bug
# Actually, let's just use the system date but simulate the bug:
DATE_STR=$(TZ=America/Los_Angeles date +%Y%m%d)

LOG_FILE="/home/user/logs/app_UTC_${DATE_STR}.log"

if [ ! -f "$LOG_FILE" ]; then
    # Fallback for the test environment to ensure it finds *a* file, but triggers the bug
    LOG_FILE=$(ls /home/user/logs/app_UTC_*.log | head -n 1)
fi

START_TS=$(grep EVENT_START "$LOG_FILE" | awk '{print $2}')
END_TS=$(grep EVENT_END "$LOG_FILE" | awk '{print $2}')

# Calculate duration in milliseconds
DURATION_MS=$((END_TS - START_TS))

# Convert to seconds (Bug 2: Precision loss due to integer division)
DURATION_SEC=$((DURATION_MS / 1000))

# Call the helper binary
/home/user/pipeline/calc_stats "$DURATION_SEC" > /home/user/pipeline/output.txt
EOF
    chmod +x /home/user/pipeline/aggregate.sh

    # Create the C helper program
    cat <<'EOF' > /home/user/pipeline/calc_stats.c
#include <stdio.h>
#include <stdlib.h>
#include <execinfo.h>
#include <signal.h>

void handler(int sig) {
    void *array[10];
    size_t size;
    fprintf(stderr, "Error: signal %d (SIGFPE) - Division by zero or precision loss detected!\n", sig);
    size = backtrace(array, 10);
    backtrace_symbols_fd(array, size, 2);
    exit(1);
}

int main(int argc, char *argv[]) {
    signal(SIGFPE, handler);

    if (argc != 2) {
        fprintf(stderr, "Usage: %s <duration_in_seconds>\n", argv[0]);
        return 1;
    }

    double duration = atof(argv[1]);

    // Simulate crash if duration is 0 due to precision loss
    if (duration == 0.0) {
        int a = 1;
        int b = 0;
        int c = a / b; // Trigger SIGFPE
        printf("%d\n", c);
    }

    double throughput = 1000.0 / duration;
    printf("%.3f\n", throughput);
    return 0;
}
EOF

    # Compile the C program
    gcc -g /home/user/pipeline/calc_stats.c -o /home/user/pipeline/calc_stats

    # Ensure correct permissions
    chown -R user:user /home/user/pipeline /home/user/logs
    chmod -R 777 /home/user
