#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

# Create user
useradd -m -s /bin/bash user || true

# Create directory
mkdir -p /home/user/incoming_data/

# Create simulator script
cat << 'EOF' > /home/user/simulator.sh
#!/bin/bash
mkdir -p /home/user/incoming_data

# File 1
touch /home/user/incoming_data/batch_1.csv
chmod u+x /home/user/incoming_data/batch_1.csv
exec 3> /home/user/incoming_data/batch_1.csv
flock -x 3
echo "10" >&3
sleep 1
echo "25" >&3
echo "15" >&3
flock -u 3
exec 3>&-
chmod u-x /home/user/incoming_data/batch_1.csv

sleep 2

# File 2
touch /home/user/incoming_data/batch_2.csv
chmod u+x /home/user/incoming_data/batch_2.csv
exec 3> /home/user/incoming_data/batch_2.csv
flock -x 3
echo "100" >&3
echo "-10" >&3
sleep 1
echo "5" >&3
flock -u 3
exec 3>&-
chmod u-x /home/user/incoming_data/batch_2.csv

sleep 2

# File 3 (Should be ignored by aggregator initially, then processed)
touch /home/user/incoming_data/batch_3.csv
chmod u+x /home/user/incoming_data/batch_3.csv
exec 3> /home/user/incoming_data/batch_3.csv
flock -x 3
echo "77" >&3
sleep 2
echo "3" >&3
flock -u 3
exec 3>&-
chmod u-x /home/user/incoming_data/batch_3.csv

echo "Simulation complete."
EOF

chmod +x /home/user/simulator.sh

chmod -R 777 /home/user
