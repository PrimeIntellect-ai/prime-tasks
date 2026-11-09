#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc git acl
pip3 install pytest

mkdir -p /app/bin /app/corpus/clean /app/corpus/evil /home/user/k8s-manifests.git/hooks
git init --bare /home/user/k8s-manifests.git

cat << 'EOF' > /tmp/compiler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

int main() {
    FILE *f = fopen("/home/user/operator/fstab.conf", "r");
    if (!f) return 2;
    char line[256];
    int found = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strstr(line, "tmpfs") && strstr(line, "/home/user/operator/run") && strstr(line, "tmpfs") && strstr(line, "rw,nodev,nosuid,size=50M")) {
            found = 1;
            break;
        }
    }
    fclose(f);
    if (!found) return 2;

    struct stat st;
    if (stat("/home/user/operator/run", &st) != 0) return 3;
    if ((st.st_mode & 0077) != 0) return 3; // ensure g and o have no permissions

    // Check valid yaml simply by looking for basic char (mock)
    char buf[1024];
    size_t n = fread(buf, 1, sizeof(buf)-1, stdin);
    if (n > 0) { buf[n] = '\0'; if (strstr(buf, "apiVersion:") != NULL) return 0; }
    return 1;
}
EOF
gcc -O2 -s /tmp/compiler.c -o /app/bin/manifest-compiler
rm /tmp/compiler.c

cat << 'EOF' > /app/corpus/clean/app.yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
spec:
  containers:
  - name: myapp
    image: nginx
EOF

cat << 'EOF' > /app/corpus/evil/bad-app.yaml
apiVersion: v1
kind: Pod
metadata:
  name: badapp
spec:
  containers:
  - name: badapp
    image: nginx
    volumeMounts:
    - mountPath: /var/run/docker.sock
      name: dockersock
  volumes:
  - name: dockersock
    hostPath:
      path: /var/run/docker.sock
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
