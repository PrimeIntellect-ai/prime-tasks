#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/deploy.git /home/user/app /home/user/app-src

    cd /home/user/deploy.git
    git init --bare

    cat << 'EOF' > /home/user/deploy.git/hooks/post-receive
#!/bin/bash
# Broken deployment hook
while read oldrev newrev refname; do
    GIT_WORK_TREE=/home/user/app git checkout -f $newrev
done

# Fails because environment is not set up
/home/user/app/start-service.sh
EOF
    chmod +x /home/user/deploy.git/hooks/post-receive

    cd /home/user/app-src
    git init
    git remote add deploy /home/user/deploy.git

    cat << 'EOF' > start-service.sh
#!/bin/bash

if [ "${TZ:-}" != "UTC" ]; then
    echo "FATAL: Service requires UTC timezone to start. Currently: ${TZ:-UNSET}" >&2
    exit 1
fi

if [ "${LC_ALL:-}" != "C.UTF-8" ]; then
    echo "FATAL: Service requires LC_ALL=C.UTF-8 to start." >&2
    exit 1
fi

echo "READY" > /home/user/app.log
EOF
    chmod +x start-service.sh

    git add start-service.sh
    git -c user.name="Admin" -c user.email="admin@local" commit -m "Initial commit"

    chmod -R 777 /home/user
