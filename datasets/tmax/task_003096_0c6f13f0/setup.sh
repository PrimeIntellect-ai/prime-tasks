#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p "/home/user/ticket_8841/data/dir with spaces"
    echo "15" > "/home/user/ticket_8841/data/file 1.txt"
    echo "25" > "/home/user/ticket_8841/data/file2.txt"
    echo "60" > "/home/user/ticket_8841/data/dir with spaces/another file.txt"
    echo "10" > "/home/user/ticket_8841/data/dir with spaces/file_4.txt"

    cat << 'EOF' > /home/user/ticket_8841/sum_values.sh
#!/bin/bash
TARGET=$1
TOTAL=0

# Environment misconfiguration
MATH_SCALE=1

# Broken loop handling spaces
for f in $(find $TARGET -name "*.txt"); do
    val=$(cat $f)
    TOTAL=$((TOTAL + val))
done

echo $((TOTAL * MATH_SCALE))
EOF

    chmod +x /home/user/ticket_8841/sum_values.sh

    echo "export MATH_SCALE=7" >> /home/user/.bashrc
    echo "export MATH_SCALE=7" >> /etc/bash.bashrc

    chmod -R 777 /home/user
