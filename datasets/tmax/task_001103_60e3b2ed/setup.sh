#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc sqlite3
    pip3 install pytest

    mkdir -p /home/user/project/src /home/user/project/lib /home/user/project/db

    cat << 'EOF' > /home/user/project/src/hw_mock.c
int hw_init() {
    return 42;
}
EOF

    cat << 'EOF' > /home/user/project/src/metrics.c
#ifndef ENABLE_MOCK_METRICS
#error "Must have ENABLE_MOCK_METRICS defined to compile"
#endif

extern int hw_init();

double get_system_score() {
    int base = hw_init();
    return base * 3.14;
}
EOF

    cat << 'EOF' > /home/user/project/build_config.json
{
  "target": "linux_x64",
  "cflags": ["-DENABLE_MOCK_METRICS"]
}
EOF

    sqlite3 /home/user/project/db/metrics.db "CREATE TABLE results (id INTEGER PRIMARY KEY, metric_name TEXT, metric_value REAL);"
    sqlite3 /home/user/project/db/metrics.db "INSERT INTO results (metric_name, metric_value) VALUES ('baseline', 100.0);"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
