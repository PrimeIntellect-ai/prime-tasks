#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc patch
    pip3 install pytest grpcio grpcio-tools

    mkdir -p /home/user/release_prep

    cat << 'EOF' > /home/user/release_prep/billing_core.c
#include <stddef.h>

struct LineItem {
    int item_id;
    double amount;
};

double calculate_total(struct LineItem* items, int count) {
    double total = 0.0;
    for (int i = 0; i < count; i++) {
        double current = items[i].amount;
        // BUG: Even item_ids should get a 10% discount, but the buggy code adds 10%
        if (items[i].item_id % 2 == 0) {
            current = current * 1.10;
        }
        total += current;
    }
    return total;
}
EOF

    cat << 'EOF' > /home/user/release_prep/discount_fix.patch
--- billing_core.c
+++ billing_core.c
@@ -10,7 +10,7 @@
         double current = items[i].amount;
-        // BUG: Even item_ids should get a 10% discount, but the buggy code adds 10%
+        // FIX: Even item_ids get a 10% discount
         if (items[i].item_id % 2 == 0) {
-            current = current * 1.10;
+            current = current * 0.90;
         }
         total += current;
     }
EOF

    cat << 'EOF' > /home/user/release_prep/billing.proto
syntax = "proto3";

message LineItemMsg {
    int32 item_id = 1;
    double amount = 2;
}

message CalculateRequest {
    repeated LineItemMsg items = 1;
}

message CalculateResponse {
    double total = 1;
}

service BillingService {
    rpc Calculate(CalculateRequest) returns (CalculateResponse);
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
