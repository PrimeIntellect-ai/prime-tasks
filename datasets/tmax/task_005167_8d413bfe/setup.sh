#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_generator.py
import base64
import json

def generate_token(user, role, exp):
    header = {"alg": "CUSTOM", "typ": "AUTH"}
    payload = {"user": user, "role": role, "exp": exp}

    h_b64 = base64.b64encode(json.dumps(header).encode()).decode()
    p_b64 = base64.b64encode(json.dumps(payload).encode()).decode()

    data = f"{h_b64}.{p_b64}"

    # Old checksum: simple sum
    checksum = sum(ord(c) for c in data)

    return f"{data}.{checksum}"

if __name__ == "__main__":
    print(generate_token("integration_tester", "admin", 1735689600))
EOF

    cat << 'EOF' > /home/user/api_update.patch
--- ref_impl_old.py
+++ ref_impl_new.py
@@ -8,11 +8,13 @@
-    h_b64 = base64.b64encode(json.dumps(header).encode()).decode()
-    p_b64 = base64.b64encode(json.dumps(payload).encode()).decode()
+    h_b64 = base64.urlsafe_b64encode(json.dumps(header, separators=(',', ':')).encode()).decode().rstrip('=')
+    p_b64 = base64.urlsafe_b64encode(json.dumps(payload, separators=(',', ':')).encode()).decode().rstrip('=')

     data = f"{h_b64}.{p_b64}"

-    # Old checksum: simple sum
-    checksum = sum(ord(c) for c in data)
+    # New checksum: DJB2 modulo 1000000, 6 digits padded
+    h = 5381
+    for c in data:
+        h = ((h << 5) + h) + ord(c)
+    checksum = f"{abs(h) % 1000000:06d}"

     return f"{data}.{checksum}"
EOF

    chmod -R 777 /home/user
