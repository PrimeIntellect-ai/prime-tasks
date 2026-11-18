#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip patch
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/interpreter.sh
#!/bin/bash
eval_rpn() {
    local stack=()
    for token in $1; do
        if [[ "$token" =~ ^-?[0-9]+$ ]]; then
            stack+=("$token")
        else
            local b="${stack[-1]}"
            local a="${stack[-2]}"
            unset 'stack[-1]'
            unset 'stack[-2]'
            local res=$((a $token b))
            stack+=("$res")
        fi
    done
    echo "${stack[0]}"
}
eval_rpn "$1"
EOF
chmod +x /home/user/interpreter.sh

cat << 'EOF' > /home/user/fix_globbing.patch
--- interpreter.sh
+++ interpreter.sh
@@ -2,2 +2,3 @@
 eval_rpn() {
+    set -f
     local stack=()
EOF

cat << 'EOF' > /home/user/fixtures.csv
1,10 5 +
2,20 4 /
3,3 4 * 2 +
4,15 5 - 2 *
5,100 10 / 5 *
6,50 25 - 5 /
7,7 8 * 10 -
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
