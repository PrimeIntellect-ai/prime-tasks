#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest numpy scipy netCDF4 h5py Flask requests SpeechRecognition

    mkdir -p /app

    cat << 'EOF' > /tmp/gen_data.py
import numpy as np
from scipy.signal import butter, lfilter
import netCDF4 as nc

# 10 seconds at 1000 Hz
t = np.linspace(0, 10, 10000, endpoint=False)
np.random.seed(42)
noise = np.random.randn(10000)

# True filter parameters are 50 Hz and 250 Hz
b, a = butter(4, [50, 250], btype='bandpass', fs=1000)
ref = lfilter(b, a, noise)

# Noisy telemetry adds 60Hz hum, high frequency noise, and an offset of 2.0
noisy = ref + 0.5 * np.sin(2*np.pi*60*t) + 0.5 * np.random.randn(10000) + 2.0

ds = nc.Dataset('/app/trace_data.nc', 'w')
ds.createDimension('time', 10000)
v_tel = ds.createVariable('telemetry', 'f8', ('time',))
v_ref = ds.createVariable('reference', 'f8', ('time',))
v_tel[:] = noisy
v_ref[:] = ref
ds.close()
EOF
    python3 /tmp/gen_data.py

    espeak -w /app/profiling_memo.wav "The baseline ID is eight one four two."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
