#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc zip unzip tar coreutils
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/repo
cd /home/user/repo
# Create the canonical artifact
echo "CRITICAL_ARTIFACT_DATA_V1" > artifact.bin
# Create the nested archives
zip inner.zip artifact.bin
tar -czf merged.tar.gz inner.zip
# Split the archive into chunks
split -b 150 merged.tar.gz blob.part
mv blob.partaa blob.parta
mv blob.partab blob.partb
# Clean up originals so the agent must reconstruct them
rm artifact.bin inner.zip merged.tar.gz
chown -R user:user /home/user/repo

chmod -R 777 /home/user
