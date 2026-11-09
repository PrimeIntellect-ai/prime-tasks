#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/metrics.dat
10
20
30
40
50
60
70
80
90
100
110
EOF

    cat << 'EOF' > /home/user/aggregate_stats.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void process_metrics() {
    char* filepath = getenv("METRICS_FILE");
    // Missing NULL check will crash if env is missing/misconfigured
    int len = strlen(filepath); 

    FILE* f = fopen(filepath, "r");
    if (!f) {
        printf("Failed to open file\n");
        exit(1);
    }

    int* data = malloc(10 * sizeof(int));
    int count = 0;

    // Off-by-one error: <= 10 allows 11 elements to be written into a 10-element array
    while (fscanf(f, "%d", &data[count]) == 1 && count <= 10) {
        count++;
    }

    int total = 0;
    for (int i = 0; i < count && i < 10; i++) {
        total += data[i];
    }

    FILE* out = fopen("/home/user/profile_results.txt", "w");
    if (out) {
        fprintf(out, "Total: %d\n", total);
        fclose(out);
    }

    free(data);
    fclose(f);
}

int main() {
    process_metrics();
    return 0;
}
EOF

    cat << 'EOF' > /home/user/profile_run.sh
#!/bin/bash
ulimit -c unlimited

# Environment misconfiguration: typo in variable name
export METRIC_FILE="/home/user/metrics.dat"

gcc -g -o /home/user/aggregate_stats /home/user/aggregate_stats.c
/home/user/aggregate_stats
EOF

    chmod +x /home/user/profile_run.sh
    chmod -R 777 /home/user
