#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip bc
    pip3 install pytest

    mkdir -p /home/user

    bash -c '
    cat << "EOF" > /home/user/run1.csv
id,value
1,10.051
2,12.402
3,8.990
4,15.221
5,7.114
EOF

    cat << "EOF" > /home/user/run2.csv
id,value
1,10.061
2,12.392
3,9.010
4,15.221
5,7.184
EOF

    for i in {6..100}; do
      val1=$(echo "scale=3; 10 + $i/10" | bc)
      if [ $((i % 2)) -eq 0 ]; then
        val2=$(echo "scale=3; $val1 + 0.015" | bc)
      else
        val2=$(echo "scale=3; $val1 - 0.012" | bc)
      fi
      echo "$i,$val1" >> /home/user/run1.csv
      echo "$i,$val2" >> /home/user/run2.csv
    done
    '

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
