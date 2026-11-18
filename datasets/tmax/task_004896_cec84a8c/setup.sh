#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch
    pip3 install pytest

    mkdir -p /home/user/build_env
    cd /home/user/build_env

    cat << 'EOF' > deps.json
{
  "main": ["libhttp", "libauth"],
  "libhttp": ["libnet", "libcrypto"],
  "libauth": ["libdb"],
  "libcrypto": ["libnet"],
  "libnet": ["libdb", "libauth_stub"],
  "libdb": ["libfs"],
  "libfs": [],
  "libauth_stub": ["libauth"]
}
EOF

    cat << 'EOF' > build.py
import sys
import argparse

def main():
    print("Building project...")
    # Linker fails without correct order
    raise Exception("Linking failed: Undefined reference in module 'main'.")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > fix_linker.patch
--- build.py
+++ build.py
@@ -3,8 +3,22 @@

 def main():
+    parser = argparse.ArgumentParser()
+    parser.add_argument("--link-order", required=True, help="Path to link order file")
+    args = parser.parse_args()
+
     print("Building project...")
-    # Linker fails without correct order
-    raise Exception("Linking failed: Undefined reference in module 'main'.")
+    
+    with open(args.link_order, 'r') as f:
+        order = [line.strip() for line in f if line.strip()]
+        
+    with open("build_artifact.bin", "w") as f:
+        f.write("SUCCESS: " + ",".join(order) + "\n")
+    print("Build successful!")

 if __name__ == "__main__":
     main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
