#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq iproute2 net-tools
    pip3 install pytest

    mkdir -p /home/user/app/cgi-bin
    mkdir -p /home/user/app/uploads

    cat << 'EOF' > /home/user/app/cgi-bin/upload.sh
#!/bin/bash
# A vulnerable upload handler
read -r POST_DATA
# Extract filename (vulnerable to path traversal)
FILENAME=$(echo "$POST_DATA" | grep -oP 'filename="\K[^"]+')
# Write data
cat > "/home/user/app/uploads/$FILENAME"
echo "Content-type: text/plain"
echo ""
echo "File uploaded."
EOF

    chmod +x /home/user/app/cgi-bin/upload.sh

    chmod 777 /home/user/app/uploads
    touch /home/user/app/uploads/legacy_data.txt
    chmod 777 /home/user/app/uploads/legacy_data.txt

    useradd -m -s /bin/bash user || true

    # Start the dummy service when a shell is launched if it's not already running
    echo 'if ! ss -tuln | grep -q ":8080" ; then python3 -m http.server 8080 --directory /home/user/app/ & fi' >> /home/user/.bashrc

    chmod -R 777 /home/user
