#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tar gzip zip unzip gawk coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat <<EOF > /home/user/dataset_config.ini
[settings]
archive_directory=/home/user/datasets
report_output=/home/user/archive_report.json
EOF

mkdir -p /home/user/datasets
cd /home/user/datasets

# alpha_data.tar.gz
mkdir -p alpha_data/data
touch alpha_data/data/1.csv
tar -czf alpha_data.tar.gz alpha_data
HASH_ALPHA=$(sha256sum alpha_data.tar.gz | awk '{print $1}')

# beta_data.zip (zip slip)
python3 -c "import zipfile; z = zipfile.ZipFile('beta_data.zip', 'w'); z.writestr('../../home/user/.bashrc', 'echo hacked'); z.close()"
HASH_BETA=$(sha256sum beta_data.zip | awk '{print $1}')

# gamma_data.tar.gz (bad hash)
mkdir -p gamma_data/data
touch gamma_data/data/2.csv
tar -czf gamma_data.tar.gz gamma_data
HASH_GAMMA="1111222233334444555566667777888899990000aaaabbbbccccddddeeeeffff"

# delta_data.tar.gz (tar slip)
python3 -c "import tarfile; t = tarfile.open('delta_data.tar.gz', 'w:gz'); info = tarfile.TarInfo('/etc/shadow'); info.size = 4; t.addfile(info, __import__('io').BytesIO(b'root')); t.close()"
HASH_DELTA=$(sha256sum delta_data.tar.gz | awk '{print $1}')

# epsilon_data.zip (safe)
python3 -c "import zipfile; z = zipfile.ZipFile('epsilon_data.zip', 'w'); z.writestr('epsilon/info.txt', 'info'); z.close()"
HASH_EPSILON=$(sha256sum epsilon_data.zip | awk '{print $1}')

# Cleanup temporary directories
rm -rf alpha_data gamma_data

cat <<EOF > /home/user/submission_logs.txt
[Submission]
Dataset: alpha_data.tar.gz
Submitter: Alice
SHA256: $HASH_ALPHA

[Submission]
Dataset: beta_data.zip
Submitter: Bob
SHA256: $HASH_BETA

[Submission]
Dataset: gamma_data.tar.gz
Submitter: Charlie
SHA256: $HASH_GAMMA

[Submission]
Dataset: delta_data.tar.gz
Submitter: Dave
SHA256: $HASH_DELTA

[Submission]
Dataset: epsilon_data.zip
Submitter: Eve
SHA256: $HASH_EPSILON
EOF

chmod -R 777 /home/user
