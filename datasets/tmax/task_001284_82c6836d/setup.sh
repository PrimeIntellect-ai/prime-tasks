#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

mkdir -p /home/user/app
mkdir -p /home/user/logs

cat << 'EOF' > /home/user/app/server.c
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <unistd.h>
#include <string.h>

pthread_mutex_t state_mutex = PTHREAD_MUTEX_INITIALIZER;
double global_aggregate = 0.0;

int attempt_convergence(double value) {
    // Simulate complex statistical convergence
    // Hardcoded to fail for excessively high anomalous values
    if (value > 1000.0) return 0; // 0 means failure to converge
    return 1;
}

void process_metric(int metric_id, double value) {
    pthread_mutex_lock(&state_mutex);

    if (value > 100.0) {
        printf("Anomaly detected for metric %d, entering convergence loop...\n", metric_id);
        int converged = attempt_convergence(value);
        if (!converged) {
            printf("ERROR: Convergence failure for metric %d\n", metric_id);
            // BUG: Missed unlock on error path
            return;
        }
    }

    global_aggregate += value;
    printf("Successfully processed metric %d. Aggregate: %.2f\n", metric_id, global_aggregate);

    pthread_mutex_unlock(&state_mutex);
}

// Mock thread runner for compilation testing
void* worker_thread(void* arg) {
    // thread stub
    return NULL;
}

int main() {
    printf("Server running...\n");
    // Main server loop goes here
    return 0;
}
EOF

cat << 'EOF' > /home/user/logs/dispatcher.log
[2024-05-10T03:14:18] DISPATCH: Sending metric_id=101, value=45.2
[2024-05-10T03:14:19] DISPATCH: Sending metric_id=102, value=88.1
[2024-05-10T03:14:20] DISPATCH: Sending metric_id=103, value=12.5
[2024-05-10T03:14:21] DISPATCH: Sending metric_id=104, value=105.0
[2024-05-10T03:14:22] DISPATCH: Sending metric_id=105, value=1500.5
[2024-05-10T03:14:23] DISPATCH: Sending metric_id=106, value=20.0
[2024-05-10T03:14:24] ERROR: Timeout waiting for ACK on metric_id=106
[2024-05-10T03:14:25] DISPATCH: Sending metric_id=107, value=30.0
[2024-05-10T03:14:26] ERROR: Timeout waiting for ACK on metric_id=107
EOF

cat << 'EOF' > /home/user/logs/server.log
[2024-05-10T03:14:18] SERVER: Successfully processed metric 101. Aggregate: 45.20
[2024-05-10T03:14:19] SERVER: Successfully processed metric 102. Aggregate: 133.30
[2024-05-10T03:14:20] SERVER: Successfully processed metric 103. Aggregate: 145.80
[2024-05-10T03:14:21] SERVER: Anomaly detected for metric 104, entering convergence loop...
[2024-05-10T03:14:21] SERVER: Successfully processed metric 104. Aggregate: 250.80
[2024-05-10T03:14:22] SERVER: Anomaly detected for metric 105, entering convergence loop...
[2024-05-10T03:14:22] SERVER: ERROR: Convergence failure for metric 105
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
