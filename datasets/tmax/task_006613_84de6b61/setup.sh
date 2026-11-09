#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential patch binutils
    pip3 install pytest

    mkdir -p /home/user/telemetry_lib

    cat << 'EOF' > /home/user/telemetry_lib/processor.c
#include <stdio.h>

void internal_parse() {}

void telemetry_init() {
    internal_parse();
}
EOF

    cat << 'EOF' > /home/user/telemetry_lib/update.patch
--- processor.c
+++ processor.c
@@ -4,6 +4,17 @@
 void internal_parse() {}

+void internal_format() {}
+
 void telemetry_init() {
     internal_parse();
 }
+
+void telemetry_process() {
+    internal_format();
+#ifdef TARGET_ANDROID
+    printf("Android\n");
+#elif defined(TARGET_IOS)
+    printf("iOS\n");
+#endif
+}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
