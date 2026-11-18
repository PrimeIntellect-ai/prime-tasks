#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/monitor_src
    cd /home/user/monitor_src
    git init
    git config user.name "SRE"
    git config user.email "sre@example.com"

    cat << 'EOF' > monitor.cpp
#include <iostream>
int main() {
    std::cout << "Incomplete monitor" << std::endl;
    return 0;
}
EOF

    git add monitor.cpp
    git commit -m "Initial commit"

    mkdir -p .git/hooks
    cat << 'EOF' > .git/hooks/post-commit
#!/bin/bash
echo "Hook ran but did nothing useful."
EOF
    chmod +x .git/hooks/post-commit

    touch /etc/fstab

    chmod -R 777 /home/user
