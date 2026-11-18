#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip patch
pip3 install pytest

mkdir -p /home/user/build_project/src
mkdir -p /home/user/build_project/dist
mkdir -p /home/user/build_project/cache

cat << 'EOF' > /home/user/build_project/src/utils.sh
#!/bin/bash
log_msg() {
    echo "[INFO] $1"
}
EOF

cat << 'EOF' > /home/user/build_project/src/core.sh
validate_input() {
    if [ -z "$1" ]; then
        echo "Error: No input"
        exit 1
    fi
    # BUG: Vulnerability here, fixed by patch
    VULN=1
}
EOF

cat << 'EOF' > /home/user/build_project/src/main.sh
main() {
    validate_input "$1"
    log_msg "Processing $1"

    # Resource leak here
    TEMP_FILE="/home/user/build_project/cache/data_$1.tmp"
    echo "$1" > "$TEMP_FILE"

    # Needs a cleanup command here like: rm -f "$TEMP_FILE"
}

main "$1"
EOF

cat << 'EOF' > /home/user/build_project/update.patch
--- src/core.sh
+++ src/core.sh
@@ -5,5 +5,5 @@
         exit 1
     fi
-    # BUG: Vulnerability here, fixed by patch
-    VULN=1
+    # PATCHED
+    VULN=0
 }
EOF

cat << 'EOF' > /home/user/build_project/build.sh
#!/bin/bash
cat src/*.sh > dist/app.sh
chmod +x dist/app.sh
EOF
chmod +x /home/user/build_project/build.sh

useradd -m -s /bin/bash user || true
chown -R user:user /home/user/build_project
chmod -R 777 /home/user
