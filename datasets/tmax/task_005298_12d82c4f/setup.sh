#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv gcc patch nginx curl
    pip3 install pytest

    mkdir -p /home/user/project
    cd /home/user/project

    # Create buggy processor.py
    cat << 'EOF' > processor.py
from flask import Flask, request, jsonify
import ctypes

app = Flask(__name__)

# Buggy route, hardcoded bad data
@app.route('/wrong_path', methods=['GET'])
def old_process():
    return jsonify({"error": "not implemented"})
EOF

    # Create the patch file
    cat << 'EOF' > fixes.patch
--- processor.py
+++ processor.py
@@ -4,7 +4,11 @@

 app = Flask(__name__)

-# Buggy route, hardcoded bad data
-@app.route('/wrong_path', methods=['GET'])
-def old_process():
-    return jsonify({"error": "not implemented"})
+cruncher = ctypes.CDLL('./libcruncher.so')
+cruncher.get_length.argtypes = [ctypes.c_char_p]
+cruncher.get_length.restype = ctypes.c_int
+
+@app.route('/api/process', methods=['GET'])
+def process_data():
+    data = request.args.get('data', '')
+    length = cruncher.get_length(data.encode('utf-8'))
+    return jsonify({"original": data, "length": length})
EOF

    # Create cruncher.c
    cat << 'EOF' > cruncher.c
#include <string.h>

int get_length(const char* str) {
    if (!str) return 0;
    return strlen(str);
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/project
    chmod -R 777 /home/user
