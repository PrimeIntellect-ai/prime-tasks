#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user/raw_docs
mkdir -p /home/user/docs_portal

# Create actual raw doc files
touch /home/user/raw_docs/api_v1_final.md
touch /home/user/raw_docs/api_v2_final.md
touch /home/user/raw_docs/setup_guide_final.md
touch /home/user/raw_docs/architecture_v2.md
touch /home/user/raw_docs/troubleshooting_revised.md

# Create sitemap.json
cat << 'EOF' > /home/user/sitemap.json
{
  "API_Docs": {
    "Version_1": "api_v1.md",
    "Version_2": "api_v2.md"
  },
  "Manuals": {
    "Installation": "setup.md",
    "Architecture": "arch.md"
  },
  "Support": {
    "FAQ": "troubleshooting.md"
  }
}
EOF

# Create migration.log
cat << 'EOF' > /home/user/migration.log
[2023-10-01 10:00:00] UPDATE
Original: api_v1.md
New: api_v1_final.md
Reason: finalized draft

[2023-10-02 11:30:00] UPDATE
Original: api_v2.md
New: api_v2_final.md
Reason: finalized draft

[2023-10-03 09:15:00] UPDATE
Original: setup.md
New: setup_guide_final.md
Reason: nomenclature change

[2023-10-04 14:20:00] UPDATE
Original: arch.md
New: architecture_v2.md
Reason: updated to v2

[2023-10-05 16:45:00] UPDATE
Original: troubleshooting.md
New: troubleshooting_revised.md
Reason: added new known issues
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/raw_docs /home/user/sitemap.json /home/user/migration.log /home/user/docs_portal
chmod -R 777 /home/user
