#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest numpy

    mkdir -p /app/audio /app/corpus/clean /app/corpus/evil

    # Generate audio
    espeak -w /app/audio/lab_notes.wav "For the stability classifier, reject any simulation run where the dominant spectral frequency exceeds forty five Hertz, or the exponential growth factor is greater than zero point zero eight."

    # Generate CSV files
    python3 -c "
import os
import numpy as np

t = np.linspace(0, 10, 1000)

# Clean
for i in range(3):
    v = np.exp(0.05 * t) * np.sin(2 * np.pi * 20 * t)
    np.savetxt(f'/app/corpus/clean/clean_{i}.csv', np.column_stack((t, v)), delimiter=',', header='time,value', comments='')

# Evil (high frequency)
for i in range(3):
    v = np.exp(0.05 * t) * np.sin(2 * np.pi * 60 * t)
    np.savetxt(f'/app/corpus/evil/evil_freq_{i}.csv', np.column_stack((t, v)), delimiter=',', header='time,value', comments='')

# Evil (high growth)
for i in range(3):
    v = np.exp(0.15 * t) * np.sin(2 * np.pi * 20 * t)
    np.savetxt(f'/app/corpus/evil/evil_growth_{i}.csv', np.column_stack((t, v)), delimiter=',', header='time,value', comments='')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
