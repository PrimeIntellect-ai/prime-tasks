#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip expect gcc
    pip3 install pytest

    mkdir -p /home/user/source_data
    echo "important data" > /home/user/source_data/data.txt

    cat << 'EOF' > /home/user/interactive_tool.sh
#!/bin/bash
echo -n "Enter source directory: "
read src
echo -n "Enter destination archive: "
read dest
echo -n "Confirm backup? (y/n) "
read confirm

if [ "$confirm" = "y" ]; then
    if [ -d "$src" ]; then
        tar -czf "$dest" -C "$(dirname "$src")" "$(basename "$src")"
        echo "Backup completed."
    else
        echo "Source does not exist."
    fi
else
    echo "Backup cancelled."
fi
EOF
    chmod +x /home/user/interactive_tool.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
