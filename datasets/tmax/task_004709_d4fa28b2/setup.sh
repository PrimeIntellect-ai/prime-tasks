#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl ffmpeg cargo rustc
    pip3 install pytest

    mkdir -p /app
    # Generate a short synthetic video
    ffmpeg -y -f lavfi -i testsrc=duration=10:size=320x240:rate=10 -pix_fmt yuv420p /app/telemetry_feed.mp4

    mkdir -p /home/user/video_telemetry/src

    cat << 'EOF' > /home/user/video_telemetry/Cargo.toml
[package]
name = "video_telemetry"
version = "0.1.0"
edition = "2021"

[dependencies]
tokio = { version = "1", features = ["full"] }
hyper = { version = "0.14", features = ["full"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
EOF

    cat << 'EOF' > /home/user/video_telemetry/src/main.rs
use std::convert::Infallible;
use std::net::SocketAddr;
use hyper::{Body, Request, Response, Server, StatusCode};
use hyper::service::{make_service_fn, service_fn};

async fn handle_req(req: Request<Body>) -> Result<Response<Body>, Infallible> {
    // Intentional bugs and missing features to be fixed by the agent
    Ok(Response::new(Body::from("Hello World")))
}

#[tokio::main]
async fn main() {
    let addr = SocketAddr::from(([127, 0, 0, 1], 8080));
    let make_svc = make_service_fn(|_conn| async {
        Ok::<_, Infallible>(service_fn(handle_req))
    });
    let server = Server::bind(&addr).serve(make_svc);
    println!("Listening on http://{}", addr);
    if let Err(e) = server.await {
        eprintln!("server error: {}", e);
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
