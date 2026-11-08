#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip patch
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/build_scripts

    cat << 'EOF' > /home/user/build_scripts/android_build.py
import ios_build

def build_apk():
    print("Building Android APK...")
    return True

def get_shared_config():
    return {"version": "1.0.0", "ndk": "21.4.7075529"}
EOF

    cat << 'EOF' > /home/user/build_scripts/ios_build.py
import android_build

def build_ipa():
    print("Building iOS IPA...")
    return True

def get_ios_config():
    config = android_build.get_shared_config()
    config["target"] = "iOS 14.0"
    return config
EOF

    cat << 'EOF' > /home/user/build_scripts/orchestrator.py
import android_build
import ios_build

def run_polyglot_build():
    android_build.build_apk()
    ios_build.build_ipa()

if __name__ == "__main__":
    run_polyglot_build()
EOF

    cat << 'EOF' > /home/user/fix_circular.patch
--- a/android_build.py
+++ b/android_build.py
@@ -1,5 +1,4 @@
-import ios_build
-
 def build_apk():
     print("Building Android APK...")
     return True
--- a/ios_build.py
+++ b/ios_build.py
@@ -1,9 +1,8 @@
-import android_build
+from android_build import get_shared_config

 def build_ipa():
     print("Building iOS IPA...")
     return True

 def get_ios_config():
-    config = android_build.get_shared_config()
+    config = get_shared_config()
     config["target"] = "iOS 14.0"
     return config
EOF

    chown -R user:user /home/user/build_scripts
    chown user:user /home/user/fix_circular.patch

    chmod -R 777 /home/user
