#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo netcat-openbsd
    pip3 install pytest

    mkdir -p /home/user/app/clean_corpus
    mkdir -p /home/user/app/evil_corpus

    for i in $(seq 1 10); do
        cat <<EOF > /home/user/app/clean_corpus/clean_${i}.csv
source,target,weight
0,1,1
1,2,1
2,3,1
EOF
    done

    for i in $(seq 1 10); do
        echo "source,target,weight" > /home/user/app/evil_corpus/evil_${i}.csv
        for s in $(seq 100 104); do
            for t in $(seq 200 209); do
                echo "$s,$t,1" >> /home/user/app/evil_corpus/evil_${i}.csv
            done
        done
    done

    cat <<'EOF' > /home/user/app/start_services.sh
#!/bin/bash
echo "Starting services..."
EOF
    chmod +x /home/user/app/start_services.sh

    cat <<'EOF' > /home/user/app/verifier.py
import os
print("Verifier")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
