#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make jq
    pip3 install pytest

    mkdir -p /home/user/release_prep

    cat << 'EOF' > /home/user/release_prep/deployment.json
{
  "deployment": {
    "metadata": {
      "service_name": "deployment-orchestrator",
      "version": "v1.4.2"
    },
    "config": {
      "target_environment": "production",
      "region": "us-east-1"
    }
  }
}
EOF

    cat << 'EOF' > /home/user/release_prep/service.proto
syntax = "proto3";
package deploy;
import "google/protobuf/empty.proto";

message DeployRequest {
  string service_id = 1;
}

message DeployResponse {
  string status = 1;
}

service DeploymentService {
  rpc Deploy(DeployRequest) returns (DeployResponse);
}
EOF

    cat << 'EOF' > /home/user/release_prep/check_util.c
#include <stdio.h>
#include <math.h>

int main() {
    double val = sqrt(16.0);
    printf("Validation complete. Status: %.1f\n", val);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/release_prep/Makefile
CC=gcc
CFLAGS=-Wall

all: check_util

check_util: check_util.o
	$(CC) $(CFLAGS) -o check_util check_util.o

check_util.o: check_util.c
	$(CC) $(CFLAGS) -c check_util.c

clean:
	rm -f check_util check_util.o
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
