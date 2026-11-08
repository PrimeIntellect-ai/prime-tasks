#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server cargo rustc curl bash
    pip3 install pytest

    mkdir -p /app/legacy_files

    bash -c 'echo -e "GREETING,\x82\xb1\x82\xf1\x82\xc9\x82\xbf\x82\xcd\nFAREWELL,\x82\xb3\x82\xe6\x82\xa4\x82\xc8\x82\xe7" > /app/legacy_files/ja.csv'
    bash -c 'echo -e "WELCOME,Bienvenue\nFAREWELL,Au revoir" | iconv -f UTF-8 -t ISO-8859-1 > /app/legacy_files/fr.csv'

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
redis-server --daemonize yes
cd /app/legacy_files && python3 -m http.server 8080 &
sleep 2
EOF
    chmod +x /app/start_services.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
