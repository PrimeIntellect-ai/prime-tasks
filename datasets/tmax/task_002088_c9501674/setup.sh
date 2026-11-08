#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline/data
    mkdir -p /home/user/pipeline/quarantine
    mkdir -p /home/user/pipeline/out

    # Create 50 files
    for i in $(seq -w 1 50); do
        if [ $i -eq 15 ]; then
            echo "STATUS: CRITICAL" | base64 > /home/user/pipeline/data/file_$i.enc
        elif [ $i -eq 37 ]; then
            # The bad file encoded in base32 instead of base64
            echo "STATUS: OK" | base32 > /home/user/pipeline/data/file_$i.enc
        else
            echo "STATUS: OK" | base64 > /home/user/pipeline/data/file_$i.enc
        fi
    done

    cat << 'EOF' > /home/user/pipeline/ingest.sh
#!/bin/bash
mkdir -p /home/user/pipeline/out
rm -f /home/user/pipeline/out/summary.txt

for f in /home/user/pipeline/data/*.enc; do
    content=$(cat "$f")

    decoded=$(echo "$content" | base64 -d 2>/dev/null)

    if [ -z "$decoded" ]; then
        echo "Error decoding $f" >&2
        exit 1
    fi

    status=$(echo "$decoded" | grep -o 'STATUS: .*' | cut -d' ' -f2)

    if [ "$status" == "CRITICAL" ]; then
        alert="YES"
    fi

    if [ "$alert" == "YES" ]; then
        echo "$(basename "$f"): CRITICAL" >> /home/user/pipeline/out/summary.txt
    fi
done
EOF

    chmod +x /home/user/pipeline/ingest.sh
    chown -R user:user /home/user/pipeline
    chmod -R 777 /home/user
