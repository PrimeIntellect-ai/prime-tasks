#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/telemetry.csv
1696150800,srv-01,System status normal | CPU:45% | Mem:8GB
1696150860,srv-02,Warn | CPU:92% | Mem:16GB
1696150920,srv-01,Load high | CPU:88% | Mem:8GB
1696150980,srv-03,Idle | CPU:12% | Mem:32GB
1696151040,srv-04,Spike detected | CPU:99% | Mem:4GB
1696151100,srv-02,Resolving | CPU:65% | Mem:16GB
1696151160,srv-05,Batch job | CPU:78% | Mem:64GB
1696151220,srv-01,Cooling down | CPU:50% | Mem:8GB
1696151280,srv-04,Throttling | CPU:95% | Mem:4GB
1696151340,srv-03,Syncing | CPU:33% | Mem:32GB
EOF

    chmod -R 777 /home/user
