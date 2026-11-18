#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc python3-pil
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Create diagram.png using Python PIL
    python3 -c "
import PIL.Image, PIL.ImageDraw
img = PIL.Image.new('RGB', (600, 200), color=(255, 255, 255))
d = PIL.ImageDraw.Draw(img)
d.text((10, 10), 'ALLOWED_NAMESPACE: secure-ops-774\nFW_PORT: 8080', fill=(0, 0, 0))
img.save('/app/diagram.png')
"

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/valid1.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: secure-ops-774
spec:
  containers:
  - name: test
    image: nginx
EOF

    cat << 'EOF' > /app/corpora/clean/valid2.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-deploy
  namespace: secure-ops-774
spec:
  template:
    spec:
      containers:
      - name: test
        image: nginx
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/wrong_ns.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: default
spec:
  containers:
  - name: test
    image: nginx
EOF

    cat << 'EOF' > /app/corpora/evil/privileged.yaml
apiVersion: v1
kind: Pod
metadata:
  name: priv-pod
  namespace: secure-ops-774
spec:
  containers:
  - name: test
    image: nginx
    securityContext:
      privileged: true
EOF

    cat << 'EOF' > /app/corpora/evil/hostnetwork.yaml
apiVersion: v1
kind: Pod
metadata:
  name: hn-pod
  namespace: secure-ops-774
spec:
  hostNetwork: true
  containers:
  - name: test
    image: nginx
EOF

    cat << 'EOF' > /app/corpora/evil/hostpath.yaml
apiVersion: v1
kind: Pod
metadata:
  name: hp-pod
  namespace: secure-ops-774
spec:
  containers:
  - name: test
    image: nginx
    volumeMounts:
    - mountPath: /test
      name: test-vol
  volumes:
  - name: test-vol
    hostPath:
      path: /data
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
