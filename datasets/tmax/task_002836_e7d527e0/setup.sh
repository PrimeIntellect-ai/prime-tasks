#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nginx
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /app/nginx

    cat << 'EOF' > /app/corpora/clean/clean1.diff
--- a/src/main.cpp
+++ b/src/main.cpp
@@ -1,3 +1,4 @@
 int main() {
+    return 0;
 }
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.asm
mov eax, 1
add eax, 2
EOF

    cat << 'EOF' > /app/corpora/evil/evil1.diff
--- a/../../../etc/shadow
+++ b/../../../etc/shadow
@@ -1,3 +1,4 @@
 root:*:18335:0:99999:7:::
+hacker:*:18335:0:99999:7:::
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.asm
mov eax, 59
syscall
EOF

    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location /api/patch {
            # TODO: route to Storage Backend
        }
        location /api/asm {
            # TODO: route to Execution Backend
        }
    }
}
EOF

    cat << 'EOF' > /app/start_services.sh
#!/bin/bash
nginx -c /app/nginx/nginx.conf &
python3 -m http.server 9001 &
python3 -m http.server 9002 &
EOF

    chmod +x /app/start_services.sh
    chmod -R 777 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
