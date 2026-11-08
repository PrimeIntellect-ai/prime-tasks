#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip jq locales
pip3 install pytest

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

mkdir -p /home/user/data

# part1.csv (ISO-8859-1)
cat << 'EOF' | iconv -f UTF-8 -t ISO-8859-1 > /home/user/data/part1.csv
id,name,email,phone
12,José PÉREZ,  Jose@example.COM,(555) 123-4567
8,  Müller ,muller@Test.org, +1-555-987-6543
105,Invalid Guy, invalid@mail.com, 123
EOF

# part2.tsv (UTF-8)
cat << 'EOF' > /home/user/data/part2.tsv
id	name	email	phone
99	Álvaro	alvaro@domain.net	1-555-111-2222
4	RENÉ	RENE@DOMAIN.NET	5552223333
EOF

# part3.json (UTF-8)
cat << 'EOF' > /home/user/data/part3.json
[
  {"id": 7, "fullName": "François", "contactEmail": " fran@cois.fr ", "phoneNumber": "+1 (555) 333-4444"}
]
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
