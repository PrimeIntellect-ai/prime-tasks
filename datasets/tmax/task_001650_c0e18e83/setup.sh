#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip openssl cargo rustc binutils procps
pip3 install pytest

mkdir -p /home/user/evidence /home/user/cracker
cd /home/user/evidence

# Generate CA
openssl req -x509 -newkey rsa:2048 -keyout ca.key -out ca.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Attacker CA/CN=ca.local"

# Generate Valid Cert
openssl req -newkey rsa:2048 -keyout valid.key -out valid.csr -nodes -subj "/C=US/ST=State/L=City/O=7d5668e21a24d52e37e9092ed1a8ea649692c81fbba8364cb05db37be1e65b75/CN=service1"
openssl x509 -req -in valid.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out valid.crt -days 365

# Generate Invalid Cert
openssl req -x509 -newkey rsa:2048 -keyout invalid.key -out invalid.crt -days 365 -nodes -subj "/C=US/ST=State/L=City/O=86b3e944b2382e75dc97a08b58dfeddd1a13460f78df2410714edbb640989f66/CN=service2"

# Compile dummy Rust binary
mkdir -p /tmp/locker/src
cat << 'EOF' > /tmp/locker/src/main.rs
fn main() {
    let salt = "_T0X1C_W4ST3_";
    println!("Locker utility. Salt loaded: {}", salt);
}
EOF

cat << 'EOF' > /tmp/locker/Cargo.toml
[package]
name = "locker"
version = "0.1.0"
edition = "2021"

[dependencies]
EOF

cd /tmp/locker
cargo build --release
cp target/release/locker /home/user/evidence/locker
strip /home/user/evidence/locker

# Create a script to start the services
cat << 'EOF' > /usr/local/bin/start_services.sh
#!/bin/bash
if ! pgrep -f "openssl s_server.*8443" > /dev/null; then
    cd /home/user/evidence
    openssl s_server -key valid.key -cert valid.crt -accept 8443 -www >/dev/null 2>&1 &
    openssl s_server -key invalid.key -cert invalid.crt -accept 8888 -www >/dev/null 2>&1 &
    sleep 1
fi
EOF
chmod +x /usr/local/bin/start_services.sh

# Ensure services start on shell interaction
echo "/usr/local/bin/start_services.sh" >> /etc/bash.bashrc
echo "/usr/local/bin/start_services.sh" >> /etc/profile

# For python tests that might not source bashrc, we can wrap python3
mv /usr/bin/python3 /usr/bin/python3.real
cat << 'EOF' > /usr/bin/python3
#!/bin/bash
/usr/local/bin/start_services.sh
exec /usr/bin/python3.real "$@"
EOF
chmod +x /usr/bin/python3

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
