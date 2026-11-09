#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/trace.log
10:00:00 MCMC_SAMPLER 1 100
10:01:00 MESH_REFINE 1 50
10:02:00 MCMC_SAMPLER 2 400
10:03:00 MESH_REFINE 2 10
10:04:00 DOMAIN_DECOMP 2 15
10:05:00 MESH_REFINE 2 20
10:06:00 MCMC_SAMPLER 1 200
10:07:00 MESH_REFINE 1 60
10:08:00 MCMC_SAMPLER 2 500
10:09:00 MESH_REFINE 2 30
10:10:00 MCMC_SAMPLER 3 50
10:11:00 MESH_REFINE 3 100
10:12:00 PIPELINE_SYNC 0 5
10:13:00 MCMC_SAMPLER 4 800
10:14:00 MESH_REFINE 4 45
10:15:00 MESH_REFINE 4 56
EOF

    chmod -R 777 /home/user
