#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip parallel
pip3 install pytest

mkdir -p /home/user/data

cat << 'EOF' > /home/user/config.env
MULTIPLIER=3.14
THRESHOLD=75000
EOF

# Use Python to generate the template to avoid Apptainer parsing double curly braces
cat << 'EOF' > /home/user/create_template.py
with open('/home/user/report.tmpl', 'w') as f:
    f.write("# Particle Energy Report\n")
    f.write("Threshold Configured: {" + "{THRESHOLD}" + "}\n")
    f.write("Total High Energy Particles: {" + "{COUNT}" + "}\n")
    f.write("Total High Energy Sum: {" + "{SUM}" + "}\n")
EOF
python3 /home/user/create_template.py
rm /home/user/create_template.py

cat << 'EOF' > /home/user/generate_data.py
import random
import math

random.seed(42)
with open('/home/user/data/particles.csv', 'w') as f:
    for i in range(1, 500001):
        x = round(random.uniform(-100, 100), 2)
        y = round(random.uniform(-100, 100), 2)
        z = round(random.uniform(-100, 100), 2)
        mass = round(random.uniform(10, 500), 2)
        f.write(f"{i},{x},{y},{z},{mass}\n")
EOF
python3 /home/user/generate_data.py
rm /home/user/generate_data.py

cat << 'EOF' > /home/user/solve.py
import math

multiplier = 3.14
threshold = 75000.0

count = 0
total_sum = 0.0

with open('/home/user/data/particles.csv', 'r') as f:
    for line in f:
        parts = line.strip().split(',')
        x, y, z, mass = float(parts[1]), float(parts[2]), float(parts[3]), float(parts[4])
        energy = mass * multiplier * math.sqrt(x**2 + y**2 + z**2)
        if energy > threshold:
            count += 1
            total_sum += energy

print(f"COUNT={count}")
print(f"SUM={total_sum:.2f}")
EOF
python3 /home/user/solve.py > /tmp/expected_values.txt
rm /home/user/solve.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
