#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip file tzdata
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/raw_logs

    # File 1: UTF-8, PST timezone
    cat << 'EOF' > /home/user/raw_logs/server_A.csv
ServerID,Timestamp,ConfigKey,Notes
srv-A,"2023-10-25 14:30:00 PST",max_connections,"Increased limit to 500
Monitoring shows spikes."
srv-A,"2023-10-26 09:15:00 PST",timeout,"Set to 30s"
EOF

    # File 2: ISO-8859-1, GMT timezone
    cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/raw_logs/server_B.csv
ServerID,Timestamp,ConfigKey,Notes
srv-B,10/25/2023 10:30 PM GMT,cache_size,"Adjusted cache size.
Old: 1024MB
New: 2048MB
Reason: Performance degradation observed during peak hours."
srv-B,10/27/2023 08:00 AM GMT,log_level,"Set to DEBUG"
EOF

    # File 3: UTF-16LE, ISO 8601 UTC
    cat << 'EOF' | iconv -f UTF-8 -t UTF-16LE > /home/user/raw_logs/server_C.csv
ServerID,Timestamp,ConfigKey,Notes
srv-C,2023-10-25T22:30:00Z,worker_threads,"Reduced to 4"
srv-C,2023-10-24T18:00:00Z,feature_flag_x,"Enabled"
EOF

    chmod -R 777 /home/user
