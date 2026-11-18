#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gawk sed
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/incoming
mkdir -p /home/user/organized
mkdir -p /home/user/scripts
touch /home/user/processing.log

# Create normal dataset 1
mkdir -p /tmp/dataset_alpha
cat << 'EOF' > /tmp/dataset_alpha/metadata.conf
Project=EpiGen
LabCode=L-101
Date=2023-10-12
EOF
cat << 'EOF' > /tmp/dataset_alpha/data1.tsv
Gene	Patient	Score
BRCA1	PAT-1234	0.98
TP53	PAT-5678	0.12
EOF
tar -czf /home/user/incoming/dataset_alpha.tar.gz -C /tmp dataset_alpha

# Create malicious dataset 2 (Zip Slip)
mkdir -p /tmp/dataset_malicious/dataset_beta
cat << 'EOF' > /tmp/dataset_malicious/dataset_beta/metadata.conf
Project=Transcriptomics
LabCode=L-202
EOF
touch /tmp/dataset_malicious/dataset_beta/data.tsv
python3 -c "
import tarfile
with tarfile.open('/home/user/incoming/dataset_malicious.tar.gz', 'w:gz') as tar:
    ti = tarfile.TarInfo('../../../../../../tmp/evil.txt')
    ti.size = 12
    with open('/tmp/evil_source.txt', 'wb') as f:
        f.write(b'hacked_file\n')
    with open('/tmp/evil_source.txt', 'rb') as f:
        tar.addfile(ti, f)

    # add normal files too
    tar.add('/tmp/dataset_malicious/dataset_beta/metadata.conf', arcname='dataset_beta/metadata.conf')
    tar.add('/tmp/dataset_malicious/dataset_beta/data.tsv', arcname='dataset_beta/data.tsv')
"

# Create normal dataset 3
mkdir -p /tmp/dataset_gamma
cat << 'EOF' > /tmp/dataset_gamma/metadata.conf
Project=Proteomics
LabCode=L-303
EOF
cat << 'EOF' > /tmp/dataset_gamma/samples.tsv
Protein	Subject	Level
KRT1	PAT-9999	14.5
EOF
tar -czf /home/user/incoming/dataset_gamma.tar.gz -C /tmp dataset_gamma

chown -R user:user /home/user
chmod -R 777 /home/user
