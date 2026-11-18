#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc build-essential libc6-dev
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/corpus.txt
Hello world
Café au lait is very good
こんにちは 世界
This has a verylongwordwithüberandotherchars inside
EOF

python3 -c '
with open("/home/user/report.tmpl", "w") as f:
    f.write("ETL Summary Report\n==================\nTotal Lines: \x7B\x7BLINES\x7D\x7D\nTotal Words: \x7B\x7BWORDS\x7D\x7D\nMax Word Length: \x7B\x7BMAX_LEN\x7D\x7D\n")
'

chmod -R 777 /home/user
