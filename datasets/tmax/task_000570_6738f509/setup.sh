#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/dataset_edges.csv
SourceDataset,TargetDataset,ProcessingTimeHours
Raw_Alpha,Clean_Alpha,2
Clean_Alpha,Merged_Data,5
Raw_Beta,Merged_Data,3
Merged_Data,Aggregated_Data,4
Aggregated_Data,Final_Omega,1
Clean_Alpha,Fast_Track,1
Fast_Track,Final_Omega,2
Raw_Alpha,Slow_Track,10
Slow_Track,Final_Omega,1
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
