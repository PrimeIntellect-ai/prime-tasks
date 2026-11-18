#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang patch
    pip3 install pytest

    mkdir -p /home/user/webapp
    cd /home/user/webapp
    go mod init example.com/webapp

    cat << 'EOF' > main.go
package main

import (
	"fmt"
	"net/http"
	_ "net/http/pprof" // For memory profiling
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "Hello")
	})
	// PATCH_INSERT_ROUTE
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/thumbnail.patch
--- main.go
+++ main.go
@@ -10,6 +10,7 @@
 	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
 		fmt.Fprint(w, "Hello")
 	})
-	// PATCH_INSERT_ROUTE
+	http.HandleFunc("/thumbnail", HandleThumbnail)
 	http.ListenAndServe(":8080", nil)
 }
--- /dev/null
+++ thumbnail.go
@@ -0,0 +1,15 @@
+package main
+
+import (
+	"fmt"
+	"net/http"
+)
+
+var LeakCache [][]byte
+
+func HandleThumbnail(w http.ResponseWriter, r *http.Request) {
+	// Simulate memory leak
+	LeakCache = append(LeakCache, make([]byte, 10*1024*1024)) 
+	
+	fmt.Fprint(w, Process())
+}
--- /dev/null
+++ proc_linux.go
@@ -0,0 +1,7 @@
+//go:build linux
+
+package main
+
+func Process() string {
+	return "Processed on Linux"
+}
--- /dev/null
+++ proc_windows.go
@@ -0,0 +1,5 @@
+package main
+
+func Process() string {
+	return "Processed on Windows"
+}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
