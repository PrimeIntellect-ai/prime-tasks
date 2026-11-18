#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Install required packages for the task
    apt-get install -y nginx apache2-utils netcat-openbsd

    # Create the user
    useradd -m -s /bin/bash user || true

    # Create routes.conf
    cat <<'EOF' > /home/user/routes.conf
# Custom Routing definitions
# Format: PATH TARGET_PORT PARAM_CHECK
/api/v1 9001 token=secret
/web 9002 NONE
EOF

    # Create generate_nginx.sh with the intentional syntax error
    cat <<'EOF' > /home/user/generate_nginx.sh
#!/bin/bash
# Generates Nginx config from routes.conf
OUT="/home/user/nginx.conf"

cat <<INNER_EOF > "$OUT"
events { worker_connections 1024; }
http {
    server {
        listen 8080;
INNER_EOF

while read -r path port param; do
    # Skip comments and empty lines
    if [[ -z "$path" || "$path" == \#* ]]; then
        continue
    fi

    echo "        location $path {" >> "$OUT"

    if [ "$param" != "NONE" ]; then
        # Parse parameter check (e.g. token=secret)
        IFS='=' read -r key val <<< "$param"
        echo "            if (\$arg_$key != \"$val\") {" >> "$OUT"
        echo "                return 403;" >> "$OUT"
        echo "            }" >> "$OUT"


    echo "            proxy_pass http://127.0.0.1:$port;" >> "$OUT"
    echo "        }" >> "$OUT"
done < /home/user/routes.conf

cat <<INNER_EOF >> "$OUT"
    }
}
INNER_EOF
EOF

    chmod +x /home/user/generate_nginx.sh
    chmod -R 777 /home/user
