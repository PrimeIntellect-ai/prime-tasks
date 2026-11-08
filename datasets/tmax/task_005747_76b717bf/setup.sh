#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/baseline
mkdir -p /home/user/staging_initial

# Create baseline files
echo "API V1 Content" > /home/user/baseline/Reference_API_v1.md
echo "User Guide Content" > /home/user/baseline/Manual_UserGuide_v1.md
echo "Readme content" > /home/user/baseline/README.txt

# Create incoming files
# 1. Changed content, needs rename
echo "API V1 Content - UPDATED" > /home/user/staging_initial/API_v1.md
# 2. Unchanged content, needs rename
echo "User Guide Content" > /home/user/staging_initial/UserGuide_v1.md
# 3. New file, needs rename
echo "API V2 Content" > /home/user/staging_initial/API_v2.md
# 4. Unrelated file, no rename needed, unchanged content
echo "Readme content" > /home/user/staging_initial/README.txt

# Create archive and cleanup
cd /home/user/staging_initial
tar -czf /home/user/incoming.tar.gz *
cd /home/user
rm -rf /home/user/staging_initial

# Create rules.json
cat << 'EOF' > /home/user/rules.json
{
  "API_": "Reference_API_",
  "UserGuide_": "Manual_UserGuide_"
}
EOF

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
