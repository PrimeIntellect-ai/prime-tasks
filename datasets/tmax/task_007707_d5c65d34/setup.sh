#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go git patch curl
    pip3 install pytest

    mkdir -p /home/user/math-api
    cd /home/user/math-api
    go mod init math-api

    cat << 'EOF' > main.go
package main

import (
	"fmt"
	"net/http"
)

func main() {
	fmt.Println("Starting server on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/pr-123.patch
diff --git a/main.go b/main.go
index 1234567..89abcdef 100644
--- a/main.go
+++ b/main.go
@@ -3,9 +3,33 @@ package main
 import (
 	"fmt"
 	"net/http"
+	"encoding/json"
+	"github.com/go-chi/chi/v5"
 )

+type VarianceRequest struct {
+	Numbers []float64 `json:"numbers"`
+}
+
+type VarianceResponse struct {
+	Variance float64 `json:"variance"`
+}
+
 func main() {
+	r := chi.NewRouter()
+	r.Post("/variance", func(w http.ResponseWriter, r *http.Request) {
+		var req VarianceRequest
+		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
+			http.Error(w, err.Error(), http.StatusBadRequest)
+			return
+		}
+		
+		v := CalculateVariance(req.Numbers)
+		w.Header().Set("Content-Type", "application/json")
+		json.NewEncoder(w).Encode(VarianceResponse{Variance: v})
+	})
+
 	fmt.Println("Starting server on :8080")
-	http.ListenAndServe(":8080", nil)
+	http.ListenAndServe(":8080", r)
 }
diff --git a/stats.go b/stats.go
new file mode 100644
index 0000000..abcdef1
--- /dev/null
+++ b/stats.go
@@ -0,0 +1,22 @@
+package main
+
+func CalculateVariance(data []float64) float64 {
+	if len(data) == 0 {
+		return 0.0
+	}
+	if len(data) == 1 {
+		return 0.0
+	}
+
+	var sum float64
+	for _, v := range data {
+		sum += v
+	}
+	mean := sum / float64(len(data))
+
+	var sqSum float64
+	for _, v := range data {
+		sqSum += (v - mean) * (v - mean)
+	}
+	return sqSum / float64(len(data)-1) // Bug: Sample variance instead of population
+}
diff --git a/stats_test.go b/stats_test.go
new file mode 100644
index 0000000..1234567
--- /dev/null
+++ b/stats_test.go
@@ -0,0 +1,18 @@
+package main
+
+import (
+	"testing"
+	"math"
+)
+
+func TestCalculateVariance(t *testing.T) {
+	data := []float64{10.5, 20.0, 30.5, 40.0}
+	expected := 122.9375 // Population variance
+	
+	result := CalculateVariance(data)
+	
+	// allow small floating point inaccuracy
+	if math.Abs(result - expected) > 1e-6 {
+		t.Errorf("Expected %f, got %f", expected, result)
+	}
+}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/math-api
    chown user:user /home/user/pr-123.patch
    chmod -R 777 /home/user
