#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/pipeline_jobs.txt
Job1:011005FF
Job2:010A06010A06010A06010A06FF
Job3:011905010A02FF
Job4:01FB05FF
Job5:012001040405FF
Job6:02FF
Job7:01050601000603FF
EOF

    chmod -R 777 /home/user
