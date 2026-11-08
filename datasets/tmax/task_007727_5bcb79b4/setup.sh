#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

mkdir -p /home/user

# Create the buggy script
cat << 'EOF' > /home/user/parse_pcap.sh
#!/bin/bash
file=$1
count=0
declare -a lengths
while read -r ts src dst proto len; do
    lengths[$count]=$len
    ((count++))
done < "$file"

i=0
max=${#lengths[@]}
total=0

# Bug 1: Boundary condition / off-by-one
# condition should be -lt, not -le, causing an out-of-bounds read on the last iteration
while [ $i -le $max ]; do
    len=${lengths[$i]}

    # Bug 2: Loop termination / infinite loop
    # If len is 0, the script continues without incrementing i
    if [[ "$len" == "0" ]]; then
        continue
    fi

    total=$((total + len))
    ((i++))
done
echo "Total: $total"
EOF

chmod +x /home/user/parse_pcap.sh

# Create the traffic log
rm -f /home/user/traffic.log
for i in $(seq 1 1000); do
    if [ $i -eq 432 ]; then
        echo "2023-10-10T10:00:00Z 192.168.1.1 10.0.0.1 TCP 0" >> /home/user/traffic.log
    elif [ $i -eq 1000 ]; then
        echo "2023-10-10T10:00:00Z 192.168.1.1 10.0.0.1 TCP 50" >> /home/user/traffic.log
    else
        echo "2023-10-10T10:00:00Z 192.168.1.1 10.0.0.1 TCP 100" >> /home/user/traffic.log
    fi
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
