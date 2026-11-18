#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server cargo rustc protobuf-compiler
    pip3 install pytest flask redis grpcio grpcio-tools protobuf

    useradd -m -s /bin/bash user || true

    APP_DIR="/home/user/app"
    mkdir -p $APP_DIR/services/rust_signer/src
    mkdir -p $APP_DIR/services/python_gateway
    mkdir -p $APP_DIR/proto
    mkdir -p $APP_DIR/corpora/evil
    mkdir -p $APP_DIR/corpora/clean

    # Protobuf definition
    cat << 'EOF' > $APP_DIR/proto/manifest.proto
syntax = "proto3";
package manifest;
service Signer {
    rpc SignManifest (ManifestRequest) returns (SignResponse);
}
message ManifestRequest {
    string app_name = 1;
    string version = 2;
    string command = 3;
}
message SignResponse {
    string signature = 1;
}
EOF

    # Rust Cargo.toml
    cat << 'EOF' > $APP_DIR/services/rust_signer/Cargo.toml
[package]
name = "rust_signer"
version = "0.1.0"
edition = "2021"

[dependencies]
tonic = "0.9"
prost = "0.11"
tokio = { version = "1.0", features = ["macros", "rt-multi-thread"] }

[build-dependencies]
tonic-build = "0.9"
EOF

    # Rust build.rs
    cat << 'EOF' > $APP_DIR/services/rust_signer/build.rs
fn main() -> Result<(), Box<dyn std::error::Error>> {
    tonic_build::compile_protos("../../proto/manifest.proto")?;
    Ok(())
}
EOF

    # Rust main.rs
    cat << 'EOF' > $APP_DIR/services/rust_signer/src/main.rs
use tonic::{transport::Server, Request, Response, Status};
use manifest::signer_server::{Signer, SignerServer};
use manifest::{ManifestRequest, SignResponse};

pub mod manifest {
    tonic::include_proto!("manifest");
}

#[derive(Debug, Default)]
pub struct MySigner {}

fn hash(s: &String) -> String {
    format!("hash_{}", s)
}

#[tonic::async_trait]
impl Signer for MySigner {
    async fn sign_manifest(
        &self,
        request: Request<ManifestRequest>,
    ) -> Result<Response<SignResponse>, Status> {
        let req = request.into_inner();
        let app = req.app_name;
        let vers = req.version;
        let tag = format!("{}-{}", app, vers);
        let sig = hash(&app);

        let reply = SignResponse {
            signature: sig,
        };
        Ok(Response::new(reply))
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let addr = "[::1]:50051".parse()?;
    let signer = MySigner::default();

    Server::builder()
        .add_service(SignerServer::new(signer))
        .serve(addr)
        .await?;

    Ok(())
}
EOF

    # Python Gateway app.py
    cat << 'EOF' > $APP_DIR/services/python_gateway/app.py
from flask import Flask, request, jsonify
import redis
import grpc

app = Flask(__name__)

@app.route('/validate', methods=['POST'])
def validate():
    pass

if __name__ == '__main__':
    app.run(port=8080)
EOF

    # Start script
    cat << 'EOF' > $APP_DIR/start.sh
#!/bin/bash
redis-server --daemonize yes
cd /home/user/app/services/rust_signer
cargo run &
cd /home/user/app/services/python_gateway
python3 app.py &
wait
EOF
    chmod +x $APP_DIR/start.sh

    # Corpora files
    cat << 'EOF' > $APP_DIR/corpora/clean/1.json
{"app_name": "myapp", "version": "1.0.0", "command": "start"}
EOF

    cat << 'EOF' > $APP_DIR/corpora/evil/1.json
{"app_name": "myapp", "version": "1.0.0", "command": "start && rm -rf /"}
EOF

    chmod -R 777 /home/user
