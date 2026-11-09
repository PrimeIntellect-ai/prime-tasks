#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        binutils \
        gdb \
        strace \
        python3-netcdf4 \
        python3-numpy \
        python3-h5py

    pip3 install pytest

    mkdir -p /app /home/user

    # Create the C source for the oracle
    cat << 'EOF' > /tmp/bio_sim.c
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    if(argc != 5) return 1;
    double P = atof(argv[1]);
    double r = atof(argv[2]);
    double K = atof(argv[3]);
    double T_max = atof(argv[4]);

    double t = 0.0;
    double dt = 0.1;

    while(t < T_max) {
        double dP = r * P * (1.0 - P / K);

        // divergent adaptation logic
        if (dP > 10.0) {
            dt = 0.05;
        } else if (dP < 1.0) {
            dt = 0.2;
        } else {
            dt = 0.1;
        }

        if (t + dt > T_max) {
            dt = T_max - t;
        }

        P = P + dP * dt;
        t = t + dt;

        if (P < 0.0 || P > 1000000.0) {
            P = -1.0;
            break;
        }
    }
    printf("%.5f\n", P);
    return 0;
}
EOF

    # Compile, strip, and clean up
    gcc -O0 -o /app/bio_sim /tmp/bio_sim.c -lm
    strip /app/bio_sim
    rm /tmp/bio_sim.c

    # Generate the NetCDF raw inputs file
    cat << 'EOF' > /tmp/make_nc.py
import netCDF4 as nc
import numpy as np

np.random.seed(42)
ds = nc.Dataset('/home/user/raw_inputs.nc', 'w', format='NETCDF4')
ds.createDimension('sample', 50)

P0 = ds.createVariable('P0', 'f8', ('sample',))
r = ds.createVariable('r', 'f8', ('sample',))
K = ds.createVariable('K', 'f8', ('sample',))
Tmax = ds.createVariable('Tmax', 'f8', ('sample',))

P0[:] = np.random.uniform(0.5, 20.0, 50)
r[:] = np.random.uniform(0.1, 2.0, 50)
K[:] = np.random.uniform(100.0, 200.0, 50)
Tmax[:] = np.random.uniform(5.0, 15.0, 50)

ds.close()
EOF

    python3 /tmp/make_nc.py
    rm /tmp/make_nc.py

    chmod 755 /app/bio_sim

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
