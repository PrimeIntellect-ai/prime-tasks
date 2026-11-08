#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest pandas

    mkdir -p /home/user/raw_data

    cat << 'EOF' > /home/user/raw_data/data_1.csv
wavelength,intensity
10.0,1.0
11.0,2.0
12.0,10.0
13.0,2.0
14.0,1.0
15.0,1.0
16.0,3.0
17.0,8.0
18.0,3.0
19.0,1.0
20.0,1.0
21.0,5.0
22.0,15.0
23.0,5.0
24.0,1.0
EOF

    cat << 'EOF' > /home/user/raw_data/data_2.csv
wavelength,intensity
10.0,0.5
11.0,0.5
12.0,5.0
13.0,0.5
14.0,0.5
15.0,0.5
16.0,0.5
EOF

    cat << 'EOF' > /home/user/raw_data/data_3.csv
wavelength,intensity
10.0,1.0
11.0,1.0
12.0,1.0
13.0,4.0
14.0,12.0
15.0,4.0
16.0,1.0
17.0,1.0
18.0,6.0
19.0,14.0
20.0,6.0
21.0,1.0
22.0,1.0
23.0,5.0
24.0,10.0
25.0,5.0
26.0,1.0
EOF

    cat << 'EOF' > /tmp/solve.py
import os
import glob
import pandas as pd

files = glob.glob('/home/user/raw_data/*.csv')
res = []
for f in files:
    df = pd.read_csv(f)
    n = len(df)
    smoothed = [0.0]*n
    for i in range(2, n-2):
        smoothed[i] = sum(df['intensity'].iloc[i-2:i+3]) / 5.0

    peaks = []
    for i in range(1, n-1):
        if smoothed[i] > smoothed[i-1] and smoothed[i] > smoothed[i+1]:
            peaks.append((smoothed[i], df['wavelength'].iloc[i]))

    peaks.sort(reverse=True, key=lambda x: x[0])
    p1 = peaks[0][1] if len(peaks)>0 else 0.0
    p2 = peaks[1][1] if len(peaks)>1 else 0.0
    p3 = peaks[2][1] if len(peaks)>2 else 0.0
    res.append({
        'filename': os.path.basename(f),
        'peak1_wl': f"{p1:.1f}",
        'peak2_wl': f"{p2:.1f}",
        'peak3_wl': f"{p3:.1f}"
    })

res = sorted(res, key=lambda x: x['filename'])
with open('/home/user/expected_training_data.csv', 'w') as out:
    out.write("filename,peak1_wl,peak2_wl,peak3_wl\n")
    for r in res:
        out.write(f"{r['filename']},{r['peak1_wl']},{r['peak2_wl']},{r['peak3_wl']}\n")
EOF
    python3 /tmp/solve.py

    cat << 'EOF' > /tmp/verify.sh
#!/bin/bash
if diff -q /home/user/training_data.csv /home/user/expected_training_data.csv; then
    exit 0
else
    exit 1
fi
EOF
    chmod +x /tmp/verify.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
