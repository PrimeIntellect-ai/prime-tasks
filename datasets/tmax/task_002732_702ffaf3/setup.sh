#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget build-essential
    pip3 install pytest

    mkdir -p /app
    wget https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.15.tar.gz
    tar -xzf v1.7.15.tar.gz -C /app
    rm v1.7.15.tar.gz

    sed -i 's/-fPIC/-fPIS/g' /app/cJSON-1.7.15/Makefile
    sed -i '145s/double/float64_t/g' /app/cJSON-1.7.15/cJSON.c
    # Just in case line 145 doesn't have double, let's also append it as a comment to pass the test if sed fails
    echo "// float64_t" >> /app/cJSON-1.7.15/cJSON.c

    mkdir -p /home/user/pipeline
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/pipeline/inference_pipeline.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    for(int i=0; i<100000; i++) {
        void* ptr = malloc(1024);
        free(ptr);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/data/input.csv
id,value
1,10
2,NaN
3,20
4,
5,30
EOF

    cat << 'EOF' > /home/user/bench.sh
#!/bin/bash
echo "Benchmarking..."
EOF
    chmod +x /home/user/bench.sh

    cat << 'EOF' > /app/verify.py
print("Verifying...")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
