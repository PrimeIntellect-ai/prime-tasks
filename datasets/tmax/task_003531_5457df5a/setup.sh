#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk make tar gzip coreutils
pip3 install pytest

# Create /app/shdoc-0.2.tar.gz
mkdir -p /app/shdoc-0.2
cat << 'EOF' > /app/shdoc-0.2/shdoc
#!/bin/bash
AWK="/opt/bin/gawk"
$AWK '
BEGIN { print "# API Documentation\n" }
/^# @/ { sub(/^# @/, ""); print }
' "$@"
EOF

cat << 'EOF' > /app/shdoc-0.2/Makefile
PREFIX ?= /usr/local

install:
	mkdir -p $(PREFIX)/bin
	cp shdoc $(PREFIX)/bin/
	chmod +x $(PREFIX)/bin/shdoc
EOF

cd /app && tar -czf shdoc-0.2.tar.gz shdoc-0.2 && rm -rf shdoc-0.2

# Create user and /home/user
useradd -m -s /bin/bash user || true
mkdir -p /home/user/legacy_docs_temp

# Create legacy docs contents
cat << 'EOF' > /home/user/legacy_docs_temp/mapping.conf
intro.md:basics/introduction.md
deploy_script.sh:scripts/deploy.sh
EOF

cat << 'EOF' > /home/user/legacy_docs_temp/intro.md
This is an intro.
Check out the [[Setup Guide]] and [[Wiki Links]].
Also [Markdown](links.md).
EOF

cat << 'EOF' > /home/user/legacy_docs_temp/deploy_script.sh
#!/bin/bash
# @name deploy
# @description Deploys the app
echo "Deploying"
EOF

# Create tarball and md5
cd /home/user/legacy_docs_temp
tar -czf /home/user/legacy_docs.tar.gz *
cd /home/user
md5sum legacy_docs.tar.gz > legacy_docs.md5
rm -rf /home/user/legacy_docs_temp

chmod -R 777 /home/user /app
