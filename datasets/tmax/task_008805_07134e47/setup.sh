#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/perf_test

    cat << 'EOF' > /home/user/perf_test/cruncher.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h>
#include <time.h>

long long current_timestamp() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main() {
    FILE *log = fopen("/home/user/perf_test/crunch.log", "w");
    if (!log) return 1;

    int id;
    double val;
    while (scanf("%d %lf", &id, &val) == 2) {
        fprintf(log, "[%lld] START ID:%d\n", current_timestamp(), id);
        fflush(log);

        double result = sqrt(val);

        // Artificial bottleneck for ID 84
        if (id == 84) {
            sleep(2);
        }

        fprintf(log, "[%lld] END ID:%d RESULT:%.2f\n", current_timestamp(), id, result);
        fflush(log);
    }
    fclose(log);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/perf_test/generator.sh
#!/bin/bash
> /home/user/perf_test/gen.log
for i in {80..90}; do
    echo "$i $(($i * $i))"
    echo "[$(date +%s%3N)] GENERATED ID:$i" >> /home/user/perf_test/gen.log
    sleep 0.1
done
EOF

    cat << 'EOF' > /home/user/perf_test/build.sh
#!/bin/bash
gcc /home/user/perf_test/cruncher.c -o /home/user/perf_test/cruncher
EOF

    cat << 'EOF' > /home/user/perf_test/run_pipeline.sh
#!/bin/bash
/home/user/perf_test/build.sh
if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi
bash /home/user/perf_test/generator.sh | /home/user/perf_test/cruncher
EOF

    chmod +x /home/user/perf_test/*.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
