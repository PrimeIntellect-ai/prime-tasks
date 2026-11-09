#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils
pip3 install pytest

# Create user
useradd -m -s /bin/bash user || true

# Setup script to create the environment, rule file, and dummy plugins
mkdir -p /home/user/plugins

# Create dummy source files
cat << 'EOF' > /home/user/plugins/libalpha.c
void plugin_init() {}
EOF

cat << 'EOF' > /home/user/plugins/libbeta.c
void wrong_init() {}
EOF

cat << 'EOF' > /home/user/plugins/libgamma.c
void gamma_init() {}
EOF

# Compile the shared libraries
gcc -shared -fPIC -o /home/user/plugins/libalpha.so /home/user/plugins/libalpha.c
gcc -shared -fPIC -o /home/user/plugins/libbeta.so /home/user/plugins/libbeta.c
gcc -shared -fPIC -o /home/user/plugins/libgamma.so /home/user/plugins/libgamma.c

# Clean up sources
rm /home/user/plugins/*.c

# Create the rules file
cat << 'EOF' > /home/user/plugin_rules.txt
libalpha.so : CLASS=ELF64 AND SYM=plugin_init
libbeta.so : CLASS=ELF64 AND SYM=beta_init
libgamma.so : CLASS=ELF32 OR SYM=gamma_init
EOF

chmod -R 777 /home/user
