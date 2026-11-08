#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > data.csv
id,score,label
1,5,0
2,15,0
3,25,0
4,35,1
5,45,1
6,55,1
7,65,1
8,75,1
9,85,1
10,95,1
EOF

    cat << 'EOF' > predict.sh
#!/bin/bash
THRESHOLD=$1
FILE=$2
echo "id,prediction"
tail -n +2 "$FILE" | while IFS=',' read -r id score label; do
  if [ "$score" -ge "$THRESHOLD" ]; then
    echo "$id,1"
  else
    echo "$id,0"
  fi
  sleep 0.05 # simulate workload for benchmarking
done
EOF
    chmod +x predict.sh

    cat << 'EOF' > evaluate.awk
BEGIN { FS=":"; correct=0; total=0 }
{
  if ($3 == $4) { correct++ }
  total++
}
END { print correct/total }
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
