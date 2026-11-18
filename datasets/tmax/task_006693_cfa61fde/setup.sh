#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip git
pip3 install pytest

mkdir -p /home/user/repo
cd /home/user/repo
git init

git config user.name "Dev"
git config user.email "dev@example.com"

for i in $(seq 1 200); do
    if [ $i -ge 90 ] && [ $i -le 95 ]; then
        # Syntax error: missing 'done'
        echo 'sum=0; for j in $(seq 1 $1); do sum=$((sum + j)); echo $sum' > calc.sh
    elif [ $i -ge 142 ]; then
        # Logic/math bug: zero-padding causes octal interpretation errors for 08 and 09
        echo 'sum=0; for j in $(seq 1 $1); do val=$(printf "%02d" $j); sum=$((sum + val)); done; echo $sum' > calc.sh
    else
        # Good implementation
        echo 'sum=0; for j in $(seq 1 $1); do sum=$((sum + j)); done; echo $sum' > calc.sh
    fi

    # Ensure file changes to avoid empty commit errors
    echo "# Commit $i" >> calc.sh

    git add calc.sh
    git commit -m "Commit $i"

    if [ $i -eq 1 ]; then
        git tag v1.0
    fi
    if [ $i -eq 200 ]; then
        git tag v2.0
    fi
    if [ $i -eq 142 ]; then
        git rev-parse HEAD > /tmp/expected_bad_commit.txt
    fi
done

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
