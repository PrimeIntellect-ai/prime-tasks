#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/query_engine/lib

    cat << 'EOF' > /home/user/query_engine/db.txt
ID=1 USER="admin" STATUS=200 MESSAGE="Login successful"
ID=2 USER="guest" STATUS=200 MESSAGE="Viewed page"
ID=3 USER="admin" OR STATUS=500 MESSAGE="Critical failure in auth module"
ID=4 USER="system" STATUS=500 MESSAGE="Disk full"
ID=5 USER="test*" STATUS=200 MESSAGE="Wildcard test"
EOF

    cat << 'EOF' > /home/user/query_engine/query.sh
#!/bin/bash
# Broken dependency include
source ./lib/bad_utils.sh

QUERY=$1
# Unsafe evaluation that crashes on globbing or syntax errors
eval "grep $QUERY db.txt"
EOF
    chmod +x /home/user/query_engine/query.sh

    cat << 'EOF' > /home/user/query_engine/lib/bad_utils.sh
alias grep='grep --color=always -n'
grep() {
    sleep 1
    command grep "$@"
}
EOF

    chmod -R 777 /home/user
