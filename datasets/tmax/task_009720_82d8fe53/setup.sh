#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pyyaml

    mkdir -p /home/user/manifests
    mkdir -p /home/user/output

    cat << 'EOF' > /home/user/manifests/web.yaml
apiVersion: v1
kind: CustomService
metadata:
  name: web-server
spec:
  image: nginx:latest
  ports:
    - port: 80
      protocol: tcp
    - port: 443
      protocol: tcp
  mounts:
    - source: /var/www/html
      destination: /usr/share/nginx/html
      fstype: ext4
EOF

    cat << 'EOF' > /home/user/manifests/db.yaml
apiVersion: v1
kind: CustomService
metadata:
  name: database
spec:
  image: postgres:14
  ports:
    - port: 5432
      protocol: tcp
  mounts:
    - source: /mnt/data/pg
      destination: /var/lib/postgresql/data
      fstype: xfs
EOF

    cat << 'EOF' > /home/user/manifests/cache.yaml
apiVersion: v1
kind: CustomService
metadata:
  name: cache-node
spec:
  image: redis:alpine
  ports:
    - port: 6379
      protocol: tcp
  mounts:
    - source: /mnt/data/redis
      destination: /data
      fstype: ext4
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
