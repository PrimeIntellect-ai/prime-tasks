#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++ tzdata
    pip3 install pytest

    mkdir -p /home/user/finops-repo
    cd /home/user/finops-repo
    git init
    git config user.email "finops@example.com"
    git config user.name "FinOps Agent"

    useradd -m -s /bin/bash user || true

    # Create wrappers to ensure the background service is running during tests and agent actions
    # Wrap pytest
    if [ -f /usr/local/bin/pytest ]; then
        mv /usr/local/bin/pytest /usr/local/bin/pytest-real
        cat << 'EOF' > /usr/local/bin/pytest
#!/bin/bash
if ! pgrep -f "http.server 10080" > /dev/null; then
    python3 -m http.server 10080 --bind 127.0.0.1 >/dev/null 2>&1 &
    sleep 0.5
fi
exec /usr/local/bin/pytest-real "$@"
EOF
        chmod +x /usr/local/bin/pytest
    fi

    # Wrap git
    mv /usr/bin/git /usr/bin/git-real
    cat << 'EOF' > /usr/bin/git
#!/bin/bash
if ! pgrep -f "http.server 10080" > /dev/null; then
    python3 -m http.server 10080 --bind 127.0.0.1 >/dev/null 2>&1 &
fi
exec /usr/bin/git-real "$@"
EOF
    chmod +x /usr/bin/git

    # Wrap g++
    mv /usr/bin/g++ /usr/bin/g++-real
    cat << 'EOF' > /usr/bin/g++
#!/bin/bash
if ! pgrep -f "http.server 10080" > /dev/null; then
    python3 -m http.server 10080 --bind 127.0.0.1 >/dev/null 2>&1 &
fi
exec /usr/bin/g++-real "$@"
EOF
    chmod +x /usr/bin/g++

    # Add to bashrc as a fallback
    echo 'if ! pgrep -f "http.server 10080" > /dev/null; then python3 -m http.server 10080 --bind 127.0.0.1 >/dev/null 2>&1 & fi' >> /home/user/.bashrc
    echo 'if ! pgrep -f "http.server 10080" > /dev/null; then python3 -m http.server 10080 --bind 127.0.0.1 >/dev/null 2>&1 & fi' >> /etc/bash.bashrc

    chown -R user:user /home/user
    chmod -R 777 /home/user
