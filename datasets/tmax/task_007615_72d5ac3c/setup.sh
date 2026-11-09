#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest

    mkdir -p /home/user/traffic_dashboard/src
    cd /home/user/traffic_dashboard

    cat << 'EOF' > Cargo.toml
[package]
name = "traffic_dashboard"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

    cat << 'EOF' > src/main.rs
use std::env;
use std::process::Command;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: {} <search_term>", args[0]);
        std::process::exit(1);
    }
    let search_term = &args[1];

    // VULNERABILITY 1: OS Command Injection (CWE-78)
    let output = Command::new("sh")
        .arg("-c")
        .arg(format!("grep '{}' traffic.log", search_term))
        .output()
        .expect("Failed to execute command");

    let logs = String::from_utf8_lossy(&output.stdout);

    println!("<html>");
    println!("<head><title>Traffic Report</title></head>");
    println!("<body>");
    println!("<h1>Traffic Report for: {}</h1>", search_term);
    println!("<ul>");

    for line in logs.lines() {
        if let Some(ua_start) = line.find("User-Agent: ") {
            let ua = &line[ua_start + 12..];
            // VULNERABILITY 2: Cross-Site Scripting (XSS) (CWE-79)
            println!("<li>User-Agent found: {}</li>", ua);
        }
    }

    println!("</ul>");
    println!("</body>");
    println!("</html>");
}
EOF

    cat << 'EOF' > traffic.log
192.168.1.10 - admin request [User-Agent: Mozilla/5.0]
192.168.1.11 - guest request [User-Agent: curl/7.68.0]
192.168.1.12 - admin malicious [User-Agent: <script>alert(1)</script>]
192.168.1.13 - normal request [User-Agent: Mozilla/5.0 ("test" & 'test')]
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/traffic_dashboard
    chmod -R 777 /home/user
