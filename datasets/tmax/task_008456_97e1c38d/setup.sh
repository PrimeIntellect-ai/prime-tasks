#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ tar
pip3 install pytest

mkdir -p /home/user/legacy_source
cd /home/user/legacy_source

cat << 'EOF' > index.csv
data_01.txt,core_module.cpp
data_02.txt,utils_strings.cpp
EOF

/bin/bash -c 'echo -e "/* Initialisation de la m\xe9moire */\nint main() { return 0; }" > data_01.txt'
/bin/bash -c 'echo -e "/* A\xf1adir funcionalidad */\nvoid add() {}" > data_02.txt'

cd /home/user
tar -czf /home/user/legacy_data.tar.gz -C /home/user legacy_source
rm -rf /home/user/legacy_source

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
