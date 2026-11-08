#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo nginx redis-server curl
    pip3 install pytest PyJWT

    mkdir -p /home/user/detector
    mkdir -p /home/user/app/nginx
    mkdir -p /home/user/app/backend/src
    mkdir -p /home/user/corpora/evil
    mkdir -p /home/user/corpora/clean

    cat << 'EOF' > /tmp/gen_jwt.py
import jwt

key = "secret_key_123"

# clean
for i in range(20):
    token = jwt.encode({"user_id": f"user{i}"}, key, algorithm="HS256")
    if isinstance(token, bytes): token = token.decode('utf-8')
    with open(f"/home/user/corpora/clean/clean_{i}.txt", "w") as f:
        f.write(token)

# evil - alg none
for i in range(5):
    token = "eyJhbGciOiAibm9uZSJ9.eyJ1c2VyX2lkIjogInVzZXIifQ."
    with open(f"/home/user/corpora/evil/evil_none_{i}.txt", "w") as f:
        f.write(token)

# evil - invalid sig
for i in range(5):
    token = jwt.encode({"user_id": f"user{i}"}, "wrong_key", algorithm="HS256")
    if isinstance(token, bytes): token = token.decode('utf-8')
    with open(f"/home/user/corpora/evil/evil_sig_{i}.txt", "w") as f:
        f.write(token)

# evil - sql inj
sql_injs = ["' OR 1=1", "UNION SELECT", "; DROP TABLE users"]
for i in range(10):
    inj = sql_injs[i % len(sql_injs)]
    token = jwt.encode({"user_id": f"user{i} {inj}"}, key, algorithm="HS256")
    if isinstance(token, bytes): token = token.decode('utf-8')
    with open(f"/home/user/corpora/evil/evil_sql_{i}.txt", "w") as f:
        f.write(token)
EOF
    python3 /tmp/gen_jwt.py

    cat << 'EOF' > /home/user/app/nginx/nginx.conf
events {}
http {
    server {
        listen 8000;
        location / {
            proxy_pass http://127.0.0.1:8080;
        }
    }
}
EOF

    cat << 'EOF' > /home/user/app/start.sh
#!/bin/bash
redis-server --daemonize yes
nginx -c /home/user/app/nginx/nginx.conf
cd /home/user/app/backend
cargo run &
EOF
    chmod +x /home/user/app/start.sh

    cat << 'EOF' > /home/user/app/backend/Cargo.toml
[package]
name = "backend"
version = "0.1.0"
edition = "2021"

[dependencies]
actix-web = "4"
jsonwebtoken = "8"
serde = { version = "1.0", features = ["derive"] }
EOF

    cat << 'EOF' > /home/user/app/backend/src/main.rs
use actix_web::{web, App, HttpServer, HttpResponse};

mod auth;

async fn secure_api() -> HttpResponse {
    HttpResponse::Ok().body("Secure data")
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| {
        App::new()
            .route("/api/secure", web::get().to(secure_api))
    })
    .bind("0.0.0.0:8080")?
    .run()
    .await
}
EOF

    cat << 'EOF' > /home/user/app/backend/src/auth.rs
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub user_id: String,
}

pub fn verify_token(token: &str) -> bool {
    let mut validation = Validation::new(Algorithm::HS256);
    validation.insecure_disable_signature_validation();
    let _ = decode::<Claims>(token, &DecodingKey::from_secret(b"secret_key_123"), &validation);
    true
}
EOF

    # Fetch dependencies to save time, but don't compile to avoid timeout
    cd /home/user/app/backend && cargo fetch || true

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
