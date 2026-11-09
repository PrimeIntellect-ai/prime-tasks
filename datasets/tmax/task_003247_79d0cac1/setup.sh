#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils gawk
    pip3 install pytest

    mkdir -p /home/user/perf_profiling/logs
    cd /home/user/perf_profiling

    # Create the buggy C binary source
    cat << 'EOF' > metric_filter.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
    if(argc != 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if(!f) return 1;
    char line[256];
    int total_duration = 0; // 32-bit signed integer will overflow > 2.14B
    while(fgets(line, sizeof(line), f)) {
        char date[64], event[64];
        int duration;
        if(sscanf(line, "%s %s %d", date, event, &duration) == 3) {
            total_duration += duration;
        }
    }
    fclose(f);
    printf("%d\n", total_duration);
    return 0;
}
EOF

    # Compile and strip the binary to hide symbols
    gcc -O2 metric_filter.c -o metric_filter
    strip metric_filter
    rm metric_filter.c

    # Create the original buggy summarize script
    cat << 'EOF' > summarize.sh
#!/bin/bash
cd /home/user/perf_profiling
rm -f results.txt
for f in logs/log_*.txt; do
    res=$(./metric_filter "$f")
    echo "$(basename $f): $res" >> results.txt
done
EOF
    chmod +x summarize.sh

    # Generate log files
    for i in $(seq 1 50); do
        fname=$(printf "log_%02d.txt" $i)
        if [ $i -eq 37 ]; then
            # Failing sum: 2,500,000,000 (overflows 32-bit int: 2500000000 - 4294967296 = -1794967296)
            awk 'BEGIN {for(j=1;j<=2500;j++) printf "[2023-10-01T12:00:00] EVENT_A 1000000\n"}' > logs/$fname
        else
            # Normal sum: 1,000,000,000
            awk 'BEGIN {for(j=1;j<=1000;j++) printf "[2023-10-01T12:00:00] EVENT_A 1000000\n"}' > logs/$fname
        fi
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/perf_profiling
    chmod -R 777 /home/user
