#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip curl netcat-openbsd procps
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/legacy-manifests
mkdir -p /home/user/dummy-bin

cat << 'EOF' > /home/user/dummy-bin/kubectl
#!/bin/bash
echo "Applying manifests: $@"
EOF
chmod +x /home/user/dummy-bin/kubectl

cat << 'EOF' > /home/user/legacy-manifests/app1.yaml
apiVersion: v1
kind: Pod
metadata:
  name: app1
EOF

cat << 'EOF' > /home/user/legacy-manifests/app2.yaml
apiVersion: v1
kind: Service
metadata:
  name: app2-svc
EOF

cat << 'EOF' > /home/user/operator-sync.sh
#!/bin/bash
# Expected to source profile here
mkdir -p "$MANIFEST_DIR/outputs"
cat "$MANIFEST_DIR"/inputs/legacy/*.yaml > "$MANIFEST_DIR/outputs/compiled.yaml" 2>/dev/null
kubectl apply -f "$MANIFEST_DIR/outputs/compiled.yaml" --dry-run=client >> "$MANIFEST_DIR/operator.log" 2>/dev/null
EOF
chmod +x /home/user/operator-sync.sh

cat << 'EOF' > /home/user/mock-cron.sh
#!/bin/bash
env -i /bin/bash -c "/home/user/operator-sync.sh"
EOF
chmod +x /home/user/mock-cron.sh

# Start metrics server automatically when shell is opened if not already running
cat << 'EOF' > /etc/profile.d/start_metrics.sh
if ! pgrep -f "python3 -m http.server 8080" > /dev/null; then
    cd /home/user && python3 -m http.server 8080 > /dev/null 2>&1 &
fi
EOF
chmod +x /etc/profile.d/start_metrics.sh

echo 'if ! pgrep -f "python3 -m http.server 8080" > /dev/null; then cd /home/user && python3 -m http.server 8080 > /dev/null 2>&1 & fi' >> /home/user/.bashrc

chmod -R 777 /home/user
