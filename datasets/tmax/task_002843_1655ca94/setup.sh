#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb parallel
    pip3 install pytest

    mkdir -p /app/data
    mkdir -p /home/user/plugin

    # Create 1000 dummy dat files
    for i in $(seq 1 1000); do
        echo "data_payload_$i" > /app/data/file_$i.dat
    done

    # Source for the stripped binary (/app/telemetry_parser.c)
    cat << 'EOF' > /tmp/telemetry_parser.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>

int main(int argc, char *argv[]) {
    // Intentional crash if config is missing to test core dump analysis
    FILE *cfg = fopen("/etc/telemetry/settings.conf", "r");
    if (!cfg) {
        // Dereference null pointer to cause segfault instead of graceful exit
        int *p = NULL;
        *p = 42; 
    }
    fclose(cfg);

    if (argc < 2) {
        printf("Usage: %s <file>\n", argv[0]);
        return 0;
    }

    char *plugin_path = getenv("PLUGIN_PATH");
    if (plugin_path) {
        void *handle = dlopen(plugin_path, RTLD_LAZY);
        if (handle) {
            void (*process)(const char*) = dlsym(handle, "process_data");
            if (process) {
                process(argv[1]);
            }
            dlclose(handle);
        }
    }

    // Simulate some IO bound work
    usleep(20000); // 20ms per file. 1000 files = 20s sequentially.

    // Mark as processed
    char out_path[512];
    snprintf(out_path, sizeof(out_path), "%s.processed", argv[1]);
    FILE *out = fopen(out_path, "w");
    if (out) {
        fprintf(out, "OK\n");
        fclose(out);
    }

    return 0;
}
EOF

    # Compile the binary, strip it, and place it in /app/
    gcc -O2 /tmp/telemetry_parser.c -o /app/telemetry_parser -ldl
    strip /app/telemetry_parser
    chmod +x /app/telemetry_parser

    # Source for the plugin with a missing math header / missing compilation instructions
    cat << 'EOF' > /home/user/plugin/parser_plugin.c
#include <stdio.h>
#include <math.h>

void process_data(const char* filepath) {
    // Useless math operation to force linking against libm
    double res = sin(0.5) * cos(0.5);
    // Suppress unused warning
    (void)res;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /app/data
    chown -R user:user /home/user/plugin
    chmod -R 777 /home/user
    chmod -R 777 /app
