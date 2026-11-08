#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app/corpora/clean /app/corpora/evil
    mkdir -p /home/user/incidents
    mkdir -p /home/user/aggregator_src

    cd /home/user/aggregator_src
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > main.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char line[256];
    long long total_aggregate = 0;
    while (fgets(line, sizeof(line), f)) {
        long long id, uid, amount, multiplier;
        if (sscanf(line, "%lld,%lld,%lld,%lld", &id, &uid, &amount, &multiplier) == 4) {
            int64_t impact = (amount * multiplier) + 1000;
            total_aggregate += impact;
        }
    }
    printf("%lld\n", total_aggregate);
    fclose(f);
    return 0;
}
EOF
    git add main.c
    git commit -m "Initial commit"

    for i in 2 3 4 5; do
        echo "// comment $i" >> main.c
        git commit -am "Commit $i"
    done

    sed -i 's/int64_t impact/int32_t impact/' main.c
    git commit -am "Memory optimization"

    for i in 7 8 9 10; do
        echo "// refactor $i" >> main.c
        git commit -am "Refactor $i"
    done

    gcc -O2 main.c -o /app/financial_aggregator
    strip -s /app/financial_aggregator

    python3 -c '
with open("/home/user/incidents/batch_99.csv", "w") as f:
    for i in range(10000):
        if i == 4502:
            f.write(f"{i},1,50000,45000\n")
        else:
            f.write(f"{i},1,10,10\n")
'

    python3 -c '
with open("/app/corpora/clean/clean.csv", "w") as f:
    for i in range(1000):
        f.write(f"{i},1,10,10\n")
with open("/app/corpora/evil/evil.csv", "w") as f:
    for i in range(1000):
        f.write(f"{i},1,50000,45000\n")
'

    chmod -R 777 /app
    chmod -R 777 /home/user
