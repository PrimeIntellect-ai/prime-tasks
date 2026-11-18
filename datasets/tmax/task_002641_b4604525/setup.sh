#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo
    pip3 install pytest maturin

    mkdir -p /app/vendored/rust_url_parser/src
    mkdir -p /app/oracle

    cat << 'EOF' > /app/vendored/rust_url_parser/pyproject.toml
[build-system]
requires = ["maturin>=1.0,<2.0"]
build-backend = "maturin"

[project]
name = "rust_url_parser"
version = "0.1.0"
requires-python = ">=3.7"

[tool.maturin]
features = ["invalid-feature"]
EOF

    cat << 'EOF' > /app/vendored/rust_url_parser/Cargo.toml
[package]
name = "rust_url_parser"
version = "0.1.0"
edition = "2021"

[lib]
name = "rust_url_parser"
crate-type = ["cdylib"]

[dependencies]
pyo3 = { version = "0.19.0", features = ["extension-module"] }
EOF

    cat << 'EOF' > /app/vendored/rust_url_parser/src/lib.rs
use pyo3::prelude::*;

#[pyfunction]
fn parse_and_encode(url: &str) -> PyResult<String> {
    unsafe {
        let _ptr = url.as_ptr().offset(100000);
    }
    Ok("{}".to_string())
}

#[pymodule]
fn rust_url_parser(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(parse_and_encode, m)?)?;
    Ok(())
}
EOF

    cat << 'EOF' > /app/oracle/legacy_url_parser_bin
#!/bin/bash
while IFS= read -r line; do
    echo '{"route": "", "protocol": "", "params": ""}'
done
EOF
    chmod +x /app/oracle/legacy_url_parser_bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
