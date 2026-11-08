#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build_logs
    mkdir -p /home/user/data

    cat << 'EOF' > /home/user/data/input_vectors.txt
1.0, 0.0, 0.0 | 0.0, 1.0, 0.0
2.5, 3.1, 0.0 | -1.0, 2.0, 5.0
0.0, 0.0, 1.0 | 0.0, 0.0, -1.0
1.0, 1.0, 1.0 | 2.0, 2.0, 2.0
0.5, 0.5, 0.5 | -0.5, -0.5, 0.5
3.0, 4.0, 0.0 | 0.0, 3.0, 4.0
0.1, 0.2, 0.3 | 0.3, 0.6, 0.9
5.0, 12.0, 0.0 | 12.0, 5.0, 0.0
EOF

    cat << 'EOF' > /home/user/process_geometry.py
import math
import sys

def calculate_angles(input_file, output_file):
    with open(input_file, 'r') as f, open(output_file, 'w') as out:
        for line in f:
            if not line.strip(): continue
            v1_str, v2_str = line.split('|')
            x1, y1, z1 = map(float, v1_str.split(','))
            x2, y2, z2 = map(float, v2_str.split(','))

            dot = x1*x2 + y1*y2 + z1*z2
            mag1 = math.sqrt(x1**2 + y1**2 + z1**2)
            mag2 = math.sqrt(x2**2 + y2**2 + z2**2)

            cos_theta = dot / (mag1 * mag2)
            angle = math.acos(cos_theta)
            out.write(f"{angle}\n")

if __name__ == '__main__':
    calculate_angles('/home/user/data/input_vectors.txt', '/home/user/output_angles.txt')
EOF

    cat << 'EOF' > /home/user/build.sh
#!/bin/bash
python3 /home/user/process_geometry.py
EOF
    chmod +x /home/user/build.sh

    # Pre-run to generate the failing log
    /home/user/build.sh > /home/user/build_logs/build.log 2>&1 || true

    chmod -R 777 /home/user
