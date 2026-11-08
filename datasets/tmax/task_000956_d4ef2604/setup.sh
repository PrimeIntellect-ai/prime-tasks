#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip wget build-essential gawk coreutils tar
pip3 install pytest

mkdir -p /app/vendored
cd /app/vendored
wget https://ftp.gnu.org/gnu/datamash/datamash-1.8.tar.gz
tar -xzf datamash-1.8.tar.gz
rm datamash-1.8.tar.gz

# Insert exit 1 at line 15
sed -i '15i exit 1' datamash-1.8/configure

cat << 'EOF' > /app/oracle_process.sh
#!/bin/bash
export PATH="/home/user/local/bin:$PATH"

awk -F',' '{
    bucket = int($1 / 60000) * 60000;
    print bucket "," 1 "," $2;
    print bucket "," 2 "," $3;
    print bucket "," 3 "," $4;
}' | \
sort -t',' -k1,1n -k2,2n | \
datamash -t',' groupby 1,2 mean 3 | \
awk -F',' '{ printf "%s,%s,%.2f\n", $1, $2, $3 }'
EOF
chmod +x /app/oracle_process.sh

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
