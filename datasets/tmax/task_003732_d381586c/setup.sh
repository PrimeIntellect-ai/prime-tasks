#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git coreutils
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    echo "Initial commit" > readme.md
    git add readme.md
    git commit -m "Init"

    echo -n "MTUgMjUgMzUgNDUgNTU=" > config.b64
    git add config.b64
    git commit -m "Add config"

    # Orphan the commit
    git reset --hard HEAD~1
    rm -f config.b64
    git reflog expire --expire=now --all

    cat << 'EOF' > build.sh
#!/bin/bash
if [ ! -f config.b64 ]; then
    echo "Error: config.b64 missing"
    exit 1
fi

# Decode config
decoded=$(cat config.b64 | base64) # BUG: Needs -d to decode
read -a arr <<< "$decoded"

score=0
count=${#arr[@]}

# BUG: off-by-one error, should be count-1
for i in $(seq 0 $count); do
    val=${arr[$i]}
    if [ -z "$val" ]; then continue; fi

    # BUG: incorrect formula
    score=$((score + val * i + 2))
done

echo "$score"
EOF

    chmod +x build.sh

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
