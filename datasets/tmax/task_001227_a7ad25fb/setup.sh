#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/artifact_utils.c
#include <string.h>

// Extracts the part of the filename before the first underscore into version_out.
// version_out is a statically allocated 16-byte buffer.
void extract_version(const char* filename, char* version_out) {
    char temp[128];
    int i = 0;
    while(filename[i] != '\0' && filename[i] != '_') {
        temp[i] = filename[i];
        i++;
    }
    temp[i] = '\0';
    // BUG: Unsafe copy. Overflows if prefix >= 16 bytes.
    strcpy(version_out, temp); 
}
EOF

    cat << 'EOF' > /home/user/workspace/artifact.proto
syntax = "proto3";

package artifact;

service ArtifactManager {
    rpc GetVersion (ArtifactRequest) returns (ArtifactResponse) {}
}

message ArtifactRequest {
    string filename = 1;
}

message ArtifactResponse {
    string version = 1;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
