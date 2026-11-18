#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip netcdf-bin
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/experiment.cdl
netcdf experiment {
variables:
    int base_offset ;
data:
    base_offset = 12 ;
}
EOF

    ncgen -o /home/user/experiment.nc /tmp/experiment.cdl

    chmod -R 777 /home/user
