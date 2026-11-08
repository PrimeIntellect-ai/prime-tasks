#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/rust_server/src
    cd /home/user/rust_server
    cargo init --bin . > /dev/null 2>&1

    cat << 'EOF' > /home/user/rust_server/src/main.rs
use std::sync::Arc;
use std::collections::HashMap;
use std::thread;

struct AppState {
    sessions: HashMap<String, String>,
}

fn main() {
    let state = Arc::new(AppState {
        sessions: HashMap::new(),
    });

    let mut handles = vec![];

    for i in 0..5 {
        let state_clone = Arc::clone(&state);
        handles.push(thread::spawn(move || {
            let session_id = format!("session_{}", i);
            let token = format!("token_{}", i);
            state_clone.sessions.insert(session_id, token);
        }));
    }

    for h in handles {
        h.join().unwrap();
    }
}
EOF

    cat << 'EOF' > /home/user/go_fix.patch
--- server.go
+++ server.go
@@ -10,7 +10,8 @@
 }

 type AppState struct {
-	sessions map[string]string
+	mu       sync.Mutex
+	sessions map[string]string
 }

 func (s *AppState) SetSession(id, token string) {
-	s.sessions[id] = token
+	s.mu.Lock()
+	defer s.mu.Unlock()
+	s.sessions[id] = token
 }
EOF

    chmod -R 777 /home/user
