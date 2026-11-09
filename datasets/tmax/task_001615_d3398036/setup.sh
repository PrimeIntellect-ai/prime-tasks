#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/pipeline_logs.csv
TaskID,PipelineID,TaskName,DurationSec,RowsProcessed
T01,PipeA,Extract,120,500
T02,PipeA,Transform,150,550
T03,PipeA,Load,45,1000
T04,PipeB,Extract,300,2000
T05,PipeB,Transform,300,0
T06,PipeB,Validate,300,100
T07,PipeB,Load,200,1900
T08,PipeC,Extract,10,0
T09,PipeC,Load,5,0
T10,PipeD,Extract,60,100
EOF

    chmod -R 777 /home/user
