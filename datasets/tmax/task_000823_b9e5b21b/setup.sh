#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user
    cat << 'EOF' > /home/user/setup_data.sh
#!/bin/bash
echo "record_id,value" > /home/user/etl_dump.csv
for i in {1..1000}; do
  if [ $i -gt 500 ]; then
    if [ $((i % 5)) -eq 0 ]; then
      echo "$i,NaN" >> /home/user/etl_dump.csv
    elif [ $((i % 7)) -eq 0 ]; then
      echo "$i,42.0" >> /home/user/etl_dump.csv
    else
      echo "$i,42" >> /home/user/etl_dump.csv
    fi
  else
    echo "$i,42" >> /home/user/etl_dump.csv
  fi
done
EOF
    chmod +x /home/user/setup_data.sh
    /home/user/setup_data.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
