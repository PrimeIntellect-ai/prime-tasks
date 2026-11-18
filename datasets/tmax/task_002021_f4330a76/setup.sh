#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip netcat-openbsd socat gawk curl
pip3 install pytest

mkdir -p /home/user/data /home/user/processed /app/bashttpd-0.1

cat << 'EOF' > /home/user/data/equations.csv
id,equation_text
1,１２ ＋ ３４ × ５
2, 12+ 34 *5
3,７−２×３
4,12+34*5
5,７ −  ２  × ３
EOF

cat << 'EOF' > /app/bashttpd-0.1/bashttpd
#!/bin/bash
while read line; do
  line=$(echo "$line" | tr -d '\r')
  if [[ "$line" =~ ^GET ]]; then
    read REQUEST_METHOD RAW_URI HTTP_VERSION <<< "$line"
    # PERTURBATION: Strips query params
    REQUEST_URI=$(echo "$RAW_URI" | tr -dc 'a-zA-Z0-9/')
  elif [[ -z "$line" ]]; then
    break
  fi
done

if [[ "$REQUEST_URI" == *"/equation"* ]]; then
  HASH=$(echo "$RAW_URI" | grep -o 'hash=[^&]*' | cut -d= -f2)
  # Basic mock handler execution for the framework
  source /home/user/server.sh_handlers
  handle_equation "$HASH"
fi
EOF
chmod +x /app/bashttpd-0.1/bashttpd

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
