#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils tar
    pip3 install pytest

    mkdir -p /home/user/repo/plugins_src
    cd /home/user/repo/plugins_src

    cat << 'EOF' > plugin_alpha.c
#include <stdio.h>
void process_record_v1() { printf("FAIL: V1 called\n"); }
EOF

    cat << 'EOF' > plugin_beta.c
#include <stdio.h>
void process_record_v2() { printf("SUCCESS_DATA_PROCESSED_V2\n"); }
EOF

    cat << 'EOF' > plugin_gamma.c
#include <stdio.h>
void process_record_v3() { printf("FAIL: V3 called\n"); }
EOF

    gcc -shared -fPIC -o plugin_alpha.so plugin_alpha.c
    gcc -shared -fPIC -o plugin_beta.so plugin_beta.c
    gcc -shared -fPIC -o plugin_gamma.so plugin_gamma.c

    tar -czf /home/user/repo/plugins.tar.gz plugin_alpha.so plugin_beta.so plugin_gamma.so
    cd /home/user/repo
    rm -rf /home/user/repo/plugins_src

    cat << 'EOF' > data_tool.c
#include <stdio.h>
extern void process_record_v2();
int main() {
    printf("INIT_ENGINE\n");
    process_record_v2();
    return 0;
}
EOF

    gcc -shared -fPIC -o libprocessor.so -x c - << 'EOF'
void process_record_v2() {}
EOF

    gcc data_tool.c -L. -lprocessor -o data_tool
    rm libprocessor.so data_tool.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
