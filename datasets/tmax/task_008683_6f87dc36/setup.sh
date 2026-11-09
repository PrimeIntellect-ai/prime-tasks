#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc ruby make
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/project
cd /home/user/project

cat << 'EOF' > build_config.json
{
  "targets": {
    "report_gen": { "lang": "ruby", "src": "report.rb", "deps": ["process_engine"] },
    "data_clean": { "lang": "python", "src": "clean.py", "deps": ["fetch_data"] },
    "process_engine": { "lang": "c", "src": "engine.c", "deps": ["data_clean"] },
    "fetch_data": { "lang": "bash", "src": "fetch.sh", "deps": [] }
  }
}
EOF

cat << 'EOF' > fetch.sh
#!/bin/bash
echo "Fetching data..."
EOF

cat << 'EOF' > clean.py
#!/usr/bin/env python3
print("Cleaning data...")
EOF

cat << 'EOF' > engine.c
#include <stdio.h>
int main() {
    printf("Processing data...\n");
    return 0;
}
EOF

cat << 'EOF' > report.rb
#!/usr/bin/env ruby
puts "Generating report..."
EOF

chmod -R 777 /home/user
