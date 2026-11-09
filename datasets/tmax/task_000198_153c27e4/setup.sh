#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip libnetcdf-dev netcdf-bin gcc upx-ucl python3-netcdf4 python3-numpy
    pip3 install pytest

    mkdir -p /app/train_data
    mkdir -p /app/test_corpus/clean
    mkdir -p /app/test_corpus/evil

    cat << 'EOF' > /app/fit_model.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <netcdf.h>

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    int ncid, varid;
    if (nc_open(argv[1], NC_NOWRITE, &ncid) != NC_NOERR) return 1;
    if (nc_inq_varid(ncid, "signal", &varid) != NC_NOERR) return 1;
    double data[1000];
    if (nc_get_var_double(ncid, varid, data) != NC_NOERR) return 1;
    nc_close(ncid);

    double sum = 0.0;
    for (int i = 1; i < 999; i++) {
        sum += fabs(data[i+1] - 2*data[i] + data[i-1]);
    }
    if (sum > 50.0) {
        printf("ERROR: Divergence detected\n");
        return 1;
    }
    printf("Fit: 1.234\n");
    return 0;
}
EOF

    gcc -O3 /app/fit_model.c -o /app/fit_model -lnetcdf -lm
    strip /app/fit_model
    upx /app/fit_model || true

    cat << 'EOF' > /app/generate_data.py
import numpy as np
import netCDF4 as nc
import os

def create_nc(filename, is_evil):
    rootgrp = nc.Dataset(filename, "w", format="NETCDF4")
    dim = rootgrp.createDimension("time", 1000)
    var = rootgrp.createVariable("signal", "f8", ("time",))

    t = np.linspace(0, 10, 1000)
    data = np.sin(t) + np.random.normal(0, 0.01, 1000)

    if is_evil:
        data[200] += 30
        data[500] -= 30

    var[:] = data
    rootgrp.close()

for i in range(50):
    create_nc(f"/app/train_data/clean_{i}.nc", False)
    create_nc(f"/app/train_data/evil_{i}.nc", True)
    create_nc(f"/app/test_corpus/clean/{i}.nc", False)
    create_nc(f"/app/test_corpus/evil/{i}.nc", True)
EOF

    python3 /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
