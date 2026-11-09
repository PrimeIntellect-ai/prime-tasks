#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip file tar
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/source_docs/nested

# 1. ISO-8859-1 Text file
echo -n "This is legacy documentation with some special chars: résumé, façade." | iconv -f UTF-8 -t ISO-8859-1 > /home/user/source_docs/legacy.txt

# 2. UTF-8 Text file
echo "Standard modern doc." > /home/user/source_docs/nested/modern.txt

# 3. Binary file masquerading as text
dd if=/dev/urandom of=/home/user/source_docs/image_data bs=1K count=1 2>/dev/null

# 4. Safe internal symlink
ln -s ../legacy.txt /home/user/source_docs/nested/safe_link.txt

# 5. Dangerous external symlinks (Zip slip simulation)
ln -s /etc/passwd /home/user/source_docs/evil_link
ln -s ../../../../../../etc/hosts /home/user/source_docs/nested/evil_link2

# Create tar
cd /home/user/source_docs
tar -cf /home/user/docs.tar *
cd /home/user
rm -rf /home/user/source_docs

mkdir -p /home/user/assets

chmod -R 777 /home/user
