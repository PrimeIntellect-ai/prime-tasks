#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_gateway.log
2024-03-15T08:00:00Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:305ms
2024-03-15T08:00:01Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:310ms
2024-03-15T08:00:02Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:350ms
2024-03-15T08:00:03Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:400ms
2024-03-15T08:00:04Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:320ms
2024-03-15T08:00:05Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:330ms
2024-03-15T08:00:06Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:340ms
2024-03-15T08:00:07Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:360ms
2024-03-15T08:00:08Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:370ms
2024-03-15T08:00:09Z | INFO | IP:10.0.0.1 action:login status:failed resp_time:380ms
2024-03-15T08:01:00Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:01Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:02Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:03Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:04Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:05Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:06Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:07Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:08Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:09Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:10Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:11Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:12Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:13Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:01:14Z | INFO | IP:10.0.0.3 action:login status:failed resp_time:500ms
2024-03-15T08:02:00Z | INFO | IP:10.0.0.2 action:login status:failed resp_time:450ms
2024-03-15T08:02:01Z | INFO | IP:10.0.0.2 action:login status:failed resp_time:450ms
2024-03-15T08:02:02Z | INFO | IP:10.0.0.2 action:login status:failed resp_time:450ms
2024-03-15T08:02:03Z | INFO | IP:10.0.0.2 action:login status:failed resp_time:450ms
2024-03-15T08:02:04Z | INFO | IP:10.0.0.2 action:login status:failed resp_time:450ms
2024-03-15T08:02:05Z | INFO | IP:10.0.0.2 action:login status:failed resp_time:450ms
2024-03-15T08:02:06Z | INFO | IP:10.0.0.2 action:login status:failed resp_time:450ms
2024-03-15T08:02:07Z | INFO | IP:10.0.0.2 action:login status:failed resp_time:450ms
2024-03-15T08:03:00Z | INFO | IP:10.0.0.4 action:login status:failed resp_time:301ms
2024-03-15T08:03:01Z | INFO | IP:10.0.0.4 action:login status:failed resp_time:301ms
2024-03-15T08:03:02Z | INFO | IP:10.0.0.4 action:login status:failed resp_time:301ms
2024-03-15T08:03:03Z | INFO | IP:10.0.0.4 action:login status:failed resp_time:301ms
2024-03-15T08:03:04Z | INFO | IP:10.0.0.4 action:login status:failed resp_time:301ms
2024-03-15T08:04:00Z | INFO | IP:10.0.0.5 action:login status:failed resp_time:800ms
2024-03-15T08:04:01Z | INFO | IP:10.0.0.5 action:login status:failed resp_time:800ms
2024-03-15T08:05:00Z | INFO | IP:192.168.1.100 action:login status:success resp_time:120ms
2024-03-15T08:05:01Z | INFO | IP:192.168.1.100 action:login status:success resp_time:900ms
2024-03-15T08:05:02Z | INFO | IP:192.168.1.101 action:login status:failed resp_time:200ms
EOF

    chmod -R 777 /home/user
