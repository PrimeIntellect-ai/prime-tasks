#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/release/patches

    # Create base.proto (1.0.0)
    cat << 'EOF' > /home/user/release/base.proto
syntax = "proto3";

package core;

service CoreService {
  rpc Ping (PingRequest) returns (PingResponse);
}

message PingRequest {}
message PingResponse {
  string status = 1;
}
EOF

    # Create patches
    # Patch 1: 1.2.0 adds HealthCheck
    cat << 'EOF' > /home/user/release/patches/add_health.patch
--- final.proto
+++ final.proto
@@ -4,6 +4,7 @@

 service CoreService {
   rpc Ping (PingRequest) returns (PingResponse);
+  rpc HealthCheck (HealthRequest) returns (HealthResponse);
 }

 message PingRequest {}
@@ -11,3 +12,6 @@
   string status = 1;
 }
+
+message HealthRequest {}
+message HealthResponse { bool ok = 1; }
EOF

    # Patch 2: 1.10.0 adds Metrics
    cat << 'EOF' > /home/user/release/patches/add_metrics.patch
--- final.proto
+++ final.proto
@@ -5,6 +5,7 @@
 service CoreService {
   rpc Ping (PingRequest) returns (PingResponse);
   rpc HealthCheck (HealthRequest) returns (HealthResponse);
+  rpc GetMetrics (MetricsRequest) returns (MetricsResponse);
 }

 message PingRequest {}
@@ -14,3 +15,6 @@

 message HealthRequest {}
 message HealthResponse { bool ok = 1; }
+
+message MetricsRequest {}
+message MetricsResponse { int32 count = 1; }
EOF

    # Patch 3: 2.0.0 removes Ping, breaking change
    cat << 'EOF' > /home/user/release/patches/remove_ping.patch
--- final.proto
+++ final.proto
@@ -3,14 +3,9 @@
 package core;

 service CoreService {
-  rpc Ping (PingRequest) returns (PingResponse);
   rpc HealthCheck (HealthRequest) returns (HealthResponse);
   rpc GetMetrics (MetricsRequest) returns (MetricsResponse);
 }
-
-message PingRequest {}
-message PingResponse {
-  string status = 1;
-}

 message HealthRequest {}
EOF

    # Patch 4: 2.1.0 adds Logging (Should NOT be applied for target 2.0.0)
    cat << 'EOF' > /home/user/release/patches/add_logging.patch
--- final.proto
+++ final.proto
@@ -5,6 +5,7 @@
 service CoreService {
   rpc HealthCheck (HealthRequest) returns (HealthResponse);
   rpc GetMetrics (MetricsRequest) returns (MetricsResponse);
+  rpc LogEvent (LogRequest) returns (LogResponse);
 }

 message HealthRequest {}
EOF

    # Create manifest
    cat << 'EOF' > /home/user/release/manifest.txt
2.1.0=patches/add_logging.patch
1.2.0=patches/add_health.patch
2.0.0=patches/remove_ping.patch
1.10.0=patches/add_metrics.patch
EOF

    chown -R user:user /home/user/release
    chmod -R 777 /home/user
