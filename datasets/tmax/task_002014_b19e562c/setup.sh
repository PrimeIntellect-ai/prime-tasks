#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ git binutils
    pip3 install pytest

    # Create the telemetry generator binary
    mkdir -p /app
    cat << 'EOF' > /app/qemu_telem_gen.c
#include <stdio.h>
#include <stdlib.h>
int main() {
    srand(42);
    for(int i=0; i<2500000; i++) {
        int vm_id = rand() % 100;
        float cpu = (float)(rand() % 10000) / 100.0f;
        float mem = (float)(rand() % 8192);
        printf("[%d] vm-%d %.2f %.2f\n", 1690000000 + i, vm_id, cpu, mem);
    }
    return 0;
}
EOF
    gcc -O3 /app/qemu_telem_gen.c -o /app/qemu_telem_gen
    strip /app/qemu_telem_gen

    # Create user
    useradd -m -s /bin/bash user || true

    # Setup git repository and pre-commit hook
    mkdir -p /home/user/repo
    cd /home/user/repo
    git init
    git config --local user.email "engineer@example.com"
    git config --local user.name "Infrastructure Engineer"

    mkdir -p /home/user/repo/.git/hooks
    cat << 'EOF' > /home/user/repo/.git/hooks/pre-commit
#!/bin/bash
g++ -O3 analyzer.cpp -o analyzer_test
if [ $? -ne 0 ]; then
    echo "Compilation failed."
    exit 1
fi
# Simple correctness check on a dummy file
echo "[1] vm-1 10.0 5" > test.log
echo "[2] vm-1 20.0 5" >> test.log
echo "[3] vm-2 99.0 5" >> test.log
RES=$(./analyzer_test test.log vm-1)
if [[ ! "$RES" == *"15"* ]]; then
    echo "Incorrect output. Expected ~15, got $RES"
    rm test.log analyzer_test
    exit 1
fi
rm test.log analyzer_test
exit 0
EOF
    chmod +x /home/user/repo/.git/hooks/pre-commit

    # Fix permissions
    chown -R user:user /home/user
    chmod -R 777 /home/user
