#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang libnetcdf-dev
    pip3 install pytest netCDF4 numpy

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_data.py
import netCDF4 as nc
import numpy as np

theta_true = 0.5
t = np.linspace(0, 10, 11)
y_true = 1.0 / (1.0 + theta_true * t)
np.random.seed(42)
y_obs = y_true + np.random.normal(0, 0.05, size=len(t))

ds = nc.Dataset('/home/user/data.nc', 'w', format='NETCDF4')
ds.createDimension('time', len(t))
time_var = ds.createVariable('t', 'f8', ('time',))
y_var = ds.createVariable('y', 'f8', ('time',))
time_var[:] = t
y_var[:] = y_obs
ds.close()
EOF

    python3 /home/user/generate_data.py

    cat << 'EOF' > /home/user/fit.go
package main

import (
	"fmt"
	"math"
	"math/rand"
	"os"

	"github.com/fhs/go-netcdf/netcdf"
)

func simulate(theta float64, t []float64) []float64 {
	y := make([]float64, len(t))
	y[0] = 1.0
	// BUG 1: dt is too large
	dt := 1.0

	current_y := 1.0
	current_t := 0.0

	for i := 1; i < len(t); i++ {
		for current_t < t[i] {
			if current_t + dt > t[i] {
				dt = t[i] - current_t
			}
			current_y = current_y - theta * current_y * current_y * dt
			current_t += dt
		}
		y[i] = current_y
	}
	return y
}

func logLikelihood(y_obs, y_sim []float64) float64 {
	sigma := 0.05
	ll := 0.0
	for i := range y_obs {
		diff := y_obs[i] - y_sim[i]
		ll += -0.5 * (diff*diff)/(sigma*sigma)
	}
	return ll
}

func main() {
	// Dummy main, the agent will rewrite this.
}
EOF

    chmod -R 777 /home/user
