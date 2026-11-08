#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    # Create the workspace directory
    mkdir -p /home/user/operator_project

    # Create the network_config.json file
    cat << 'EOF' > /home/user/operator_project/network_config.json
{"network": "10.0.0.0/24", "status": "active"}
EOF

    # Create the operator.c file
    cat << 'EOF' > /home/user/operator_project/operator.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    const char *config_path = getenv("NETWORK_CONFIG_PATH");
    if (config_path == NULL) {
        fprintf(stderr, "Error: NETWORK_CONFIG_PATH environment variable not set.\n");
        return 1;
    }

    FILE *f = fopen(config_path, "r");
    if (f == NULL) {
        fprintf(stderr, "Error: Could not open configuration file at %s\n", config_path);
        return 1;
    }

    char buffer[256];
    if (fgets(buffer, sizeof(buffer), f) == NULL) {
        fclose(f);
        return 1;
    }
    fclose(f);

    // Write success log
    FILE *log = fopen("/home/user/operator_project/deploy.log", "w");
    if (log != NULL) {
        fprintf(log, "DEPLOY_SUCCESS: Read config successfully.\n");
        fclose(log);
    }

    return 0;
}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
