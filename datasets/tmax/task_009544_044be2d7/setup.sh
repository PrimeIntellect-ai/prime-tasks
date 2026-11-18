#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk bc coreutils grep sed
    pip3 install pytest

    mkdir -p /home/user/profiling_data

    cat << 'EOF' > /home/user/profiling_data/run_N10.csv
Function,Caller,ExecutionTime_ms
Init,main,15
ComputeEigen,SolveSystem,250
ComputeEigen,RefineMesh,262
Cleanup,main,5
EOF

    cat << 'EOF' > /home/user/profiling_data/run_N20.csv
Function,Caller,ExecutionTime_ms
Init,main,15
ComputeEigen,SolveSystem,2000
ComputeEigen,RefineMesh,2050
Cleanup,main,6
EOF

    cat << 'EOF' > /home/user/profiling_data/run_N40.csv
Function,Caller,ExecutionTime_ms
Init,main,18
ComputeEigen,SolveSystem,16000
ComputeEigen,RefineMesh,16200
Cleanup,main,5
EOF

    cat << 'EOF' > /home/user/profiling_data/run_N80.csv
Function,Caller,ExecutionTime_ms
Init,main,22
ComputeEigen,SolveSystem,127000
ComputeEigen,RefineMesh,128000
Cleanup,main,8
EOF

    cat << 'EOF' > /home/user/profiling_data/run_N160.csv
Function,Caller,ExecutionTime_ms
Init,main,30
ComputeEigen,SolveSystem,1020000
ComputeEigen,RefineMesh,1030000
Cleanup,main,10
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
