#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gawk coreutils sed grep
pip3 install pytest

mkdir -p /home/user/bin
mkdir -p /home/user/results

cat << 'EOF' > /home/user/proteins.fasta
>protein_A
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
>protein_B
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
>protein_C
MTEITAAMVKELRES
>protein_D
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
MTEITAAMVKELRESTGAGMMDCKNALSETNGDFDKAVQLLREKGLGKAA
EOF

cat << 'EOF' > /home/user/bin/simulate_ode.sh
#!/bin/bash
L=$1
dt=$2
awk -v L="$L" -v dt="$dt" 'BEGIN {
    y = 1.0;
    k = L;
    for(t=0; t<=2.0; t+=dt) {
        y = y * (1 - k * dt);
        if (y > 1000 || y < -1000) { print "DIVERGED"; exit 1; }
    }
    print "STABLE"; exit 0;
}'
EOF
chmod +x /home/user/bin/simulate_ode.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
