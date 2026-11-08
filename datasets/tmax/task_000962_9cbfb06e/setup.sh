#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip time bc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/v1_data.txt
id|name|raw_math_formula
1|Alice|3.5 * 2.0
2|Bob|10 / 3
3|Charlie|2.5 + 4.1 * 2
4|David|100 - 15.75
EOF

    cat << 'EOF' > /home/user/migrate_v1_to_v2.sh
#!/bin/bash
file_content=$(cat "$1")
for line in $file_content; do
    id=$(echo $line | cut -d'|' -f1)
    name=$(echo $line | cut -d'|' -f2)
    expr=$(echo $line | cut -d'|' -f3)
    val=$(expr $expr)
    echo "$id|$name|$val"
done
EOF

    chmod +x /home/user/migrate_v1_to_v2.sh
    chmod -R 777 /home/user
