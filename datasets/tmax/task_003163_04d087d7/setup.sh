#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch make gcc
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/telemetry
    cd /home/user/telemetry

    # Create initial proto
    cat << 'EOF' > telemetry.proto
syntax = "proto3";

message DeviceStatus {
    int32 device_id = 1;
}
EOF

    # Create patch file
    cat << 'EOF' > proto.patch
--- telemetry.proto	2023-10-01 12:00:00.000000000 +0000
+++ telemetry_new.proto	2023-10-01 12:01:00.000000000 +0000
@@ -2,4 +2,9 @@

 message DeviceStatus {
     int32 device_id = 1;
+    string status = 2;
+}
+
+service TelemetryService {
+    rpc SendStatus(DeviceStatus) returns (DeviceStatus);
 }
EOF

    # Create broken Makefile (spaces instead of tabs)
    cat << 'EOF' > Makefile
verify_checksum: verify_checksum.c
    gcc -o verify_checksum verify_checksum.c
EOF

    # Create broken C file
    cat << 'EOF' > verify_checksum.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;

    int sum = 0;
    int c;
    while ((c = fgetc(f)) != EOF) {
        sum += c;
    }
    fclose(f);

    printf("Checksum: %d\n", sum) // Missing semicolon
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
