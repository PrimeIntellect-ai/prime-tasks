#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang build-essential patch
    pip3 install pytest

    mkdir -p /home/user/bashwaf
    cd /home/user/bashwaf

    # Base waf.sh
    cat << 'EOF' > /home/user/bashwaf/waf.sh
#!/bin/bash
# BashWAF Initialization
echo "Starting BashWAF..."
if [ -z "$1" ]; then
    echo "Usage: ./waf.sh <payload_file>"
    exit 1
fi
echo "Initializing engine..."

# Old logic
while read -r line; do
    id=$(echo "$line" | cut -d'|' -f1)
    echo "$id: CLEAN" >> scan_results.log
done < "$1"
EOF
    chmod +x /home/user/bashwaf/waf.sh

    # payloads.txt
    cat << 'EOF' > /home/user/bashwaf/payloads.txt
req_001|PUSH 1 PUSH 2 ADD POP
req_002|PUSH 99 MALICIOUS_SYSCALL
req_003|INVALID OPCODE
EOF

    # The patch file
    cat << 'EOF' > /home/user/pr.patch
--- waf.sh
+++ waf.sh
@@ -1,13 +1,11 @@
 #!/bin/bash
-# BashWAF Initialization
-echo "Starting BashWAF..."
+# BashWAF New FFI Engine
 if [ -z "$1" ]; then
-    echo "Usage: ./waf.sh <payload_file>"
+    echo "Need payload file"
     exit 1
 fi
-echo "Initializing engine..."

-# Old logic
+> scan_results.log
 while read -r line; do
     id=$(echo "$line" | cut -d'|' -f1)
-    echo "$id: CLEAN" >> scan_results.log
+    payload=$(echo "$line" | cut -d'|' -f2)
+    python3 ffi_wrapper.py "$payload"
+    # BUG: Fails to capture exit code properly and map it
+    echo "$id: UNKNOWN" >> scan_results.log
 done < "$1"
--- /dev/null
+++ evaluator.go
@@ -0,0 +1,31 @@
+package main
+
+import "C"
+import "strings"
+
+//export EvaluatePayload
+func EvaluatePayload(payload *C.char) C.int {
+    p := C.GoString(payload)
+    ch := make(chan int)
+    
+    go func() {
+        if strings.Contains(p, "MALICIOUS") {
+            ch <- 1
+        } else if strings.Contains(p, "INVALID") {
+            ch <- 2
+        } else {
+            ch <- 0
+        }
+        // BUG: Deadlock here if another goroutine is waiting or channel is unbuffered without receiver ready
+    }()
+    
+    return C.int(<-ch)
+}
+
+func main() {}
--- /dev/null
+++ ffi_wrapper.py
@@ -0,0 +1,10 @@
+import ctypes
+import sys
+
+lib = ctypes.CDLL('./libeval.so')
+lib.EvaluatePayload.argtypes = [ctypes.c_char_p]
+lib.EvaluatePayload.restype = ctypes.c_int
+
+payload = sys.argv[1].encode('utf-8')
+res = lib.EvaluatePayload(payload)
+sys.exit(res)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
