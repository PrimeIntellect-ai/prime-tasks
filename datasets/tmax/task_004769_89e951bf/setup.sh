#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip make
    pip3 install pytest pandas scikit-learn scipy flask fastapi uvicorn setuptools

    # Create labschema package
    mkdir -p /app/labschema-1.2.0

    cat << 'EOF' > /app/labschema-1.2.0/setup.py
from setuptools import setup
setup(name='labschema', version='1.2.0', py_modules=['labschema'])
EOF

    cat << 'EOF' > /app/labschema-1.2.0/labschema.py
class ValidationError(Exception):
    pass

def validate_clinical(row):
    if not isinstance(row.get('patient_id'), str):
        raise ValidationError("patient_id must be str")
    if not isinstance(row.get('age'), int):
        raise ValidationError("age must be int")
    if not isinstance(row.get('recovery_time'), float):
        raise ValidationError("recovery_time must be float")

def validate_biomarkers(row):
    if not isinstance(row.get('patient_id'), str):
        raise ValidationError("patient_id must be str")
    for i in range(1, 11):
        if not isinstance(row.get(f'marker_{i}'), float):
            raise ValidationError(f"marker_{i} must be float")
EOF

    cat << 'EOF' > /app/labschema-1.2.0/Makefile
install:
	pyhton3 setup.py install
EOF

    # Create data directories
    mkdir -p /home/user/data

    # Generate synthetic data
    cat << 'EOF' > /tmp/generate_data.py
import csv, json, random

random.seed(42)
clinical = []
biomarkers = []

for i in range(100):
    pid = f"P{i:03d}"
    age = random.randint(20, 80)
    rt = random.uniform(5.0, 20.0)

    if random.random() < 0.05:
        age = str(age)

    clinical.append({'patient_id': pid, 'age': age, 'recovery_time': rt})

    b_row = {'patient_id': pid}
    for j in range(1, 11):
        val = random.uniform(0, 1)
        if random.random() < 0.05:
            val = val > 0.5
        b_row[f'marker_{j}'] = val
    biomarkers.append(b_row)

with open('/home/user/data/clinical.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['patient_id', 'age', 'recovery_time'])
    writer.writeheader()
    writer.writerows(clinical)

with open('/home/user/data/biomarkers.json', 'w') as f:
    json.dump(biomarkers, f, indent=2)
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
