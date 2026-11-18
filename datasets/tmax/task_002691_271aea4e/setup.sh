#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx rustc cargo
    pip3 install pytest

    mkdir -p /app/rust_cleaner/src

    cat << 'EOF' > /app/nginx.conf
worker_processes 1;
daemon off;
events { worker_connections 1024; }
http {
    server {
        listen 127.0.0.1:8000;
        location /process {
            proxy_pass http://127.0.0.1:8080/process;
        }
    }
}
EOF

    cat << 'EOF' > /app/start.sh
#!/bin/bash
nginx -c /app/nginx.conf &
cd /app/rust_cleaner && cargo run --release &
EOF
    chmod +x /app/start.sh

    cat << 'EOF' > /app/rust_cleaner/Cargo.toml
[package]
name = "rust_cleaner"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4.3"
csv = "1.2"
strsim = "0.10"
EOF

    cat << 'EOF' > /app/rust_cleaner/src/main.rs
use actix_web::{post, web, App, HttpResponse, HttpServer, Responder, HttpRequest};
use strsim::levenshtein;

#[post("/process")]
async fn process(req: HttpRequest, body: web::Bytes) -> impl Responder {
    if let Some(auth) = req.headers().get("Authorization") {
        if auth.to_str().unwrap_or("") != "Bearer data-science-token" {
            return HttpResponse::Unauthorized().finish();
        }
    } else {
        return HttpResponse::Unauthorized().finish();
    }

    let payload = String::from_utf8_lossy(&body);
    let mut response = String::new();

    // Buggy naive splitting
    for line in payload.lines().skip(1) {
        let parts: Vec<&str> = line.split(',').collect();
        if parts.len() >= 3 {
            let id = parts[0];
            let text_a = parts[1].trim_matches('"');
            let text_b = parts[2].trim_matches('"');
            let dist = levenshtein(text_a, text_b);
            response.push_str(&format!("[ID: {}] Distance: {}\n", id, dist));
        }
    }

    HttpResponse::Ok().body(response)
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new().service(process)
    })
    .bind(("127.0.0.1", 8080))?
    .run()
    .await
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
