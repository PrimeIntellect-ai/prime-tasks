#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip rustc cargo
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/upload_handler.rs
pub fn generate_token(username: &str) -> String {
    let salt = "SuperSecretPenTestSalt2024";
    let input = format!("{}{}", username, salt);
    // Uses MD5 for token generation
    format!("{:x}", md5::compute(input))
}

pub fn save_file(filename: &str, content: &[u8]) {
    // Saves files to /tmp/uploads/
    let path = format!("/tmp/uploads/{}", filename);
    std::fs::write(path, content).unwrap();
}

pub fn get_response() -> String {
    let response = "HTTP/1.1 200 OK\r\n\
                    Content-Type: text/html\r\n\
                    \r\n\
                    <html><body><h1>File Uploaded Successfully!</h1></body></html>";
    response.to_string()
}
EOF

    chmod -R 777 /home/user
