#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy pyinstaller

mkdir -p /app
cd /app

# Create the python script for the legacy cleaner
cat << 'EOF' > cleaner.py
import sys
import numpy as np

def process(input_csv, output_csv):
    data = np.loadtxt(input_csv, delimiter=',')
    if data.ndim == 1:
        data = data.reshape(1, -1)

    out = []
    for row in data:
        F = np.fft.fft(row)
        F[32:993] = 0
        smoothed = np.fft.ifft(F).real

        left_anchor = np.mean(smoothed[:10])
        right_anchor = np.mean(smoothed[1014:])

        baseline = np.linspace(left_anchor, right_anchor, 1024)
        cleaned = smoothed - baseline
        out.append(cleaned)

    np.savetxt(output_csv, np.array(out), delimiter=',')

if __name__ == '__main__':
    if len(sys.argv) == 3:
        process(sys.argv[1], sys.argv[2])
EOF

# Build the binary using pyinstaller
pyinstaller --onefile cleaner.py
mv dist/cleaner /app/legacy_cleaner
strip /app/legacy_cleaner || true
rm -rf build dist cleaner.spec cleaner.py

# Generate raw spectra
cat << 'EOF' > generate_data.py
import numpy as np

np.random.seed(42)
data = []
for _ in range(100):
    x = np.linspace(0, 10, 1024)
    y = np.sin(2 * np.pi * 1.5 * x) + np.random.normal(0, 0.5, 1024) + 0.5 * x
    data.append(y)
np.savetxt('/app/raw_spectra.csv', np.array(data), delimiter=',')

hidden_data = []
for _ in range(1000):
    x = np.linspace(0, 10, 1024)
    y = np.cos(2 * np.pi * 2.0 * x) + np.random.normal(0, 0.8, 1024) - 0.2 * x
    hidden_data.append(y)
np.savetxt('/app/hidden_test.csv', np.array(hidden_data), delimiter=',')
EOF

python3 generate_data.py
rm generate_data.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
