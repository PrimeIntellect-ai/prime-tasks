#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/uploads

    # Create files
    echo -n "clean file" > /home/user/uploads/file_alpha.txt
    echo -n "tampered data" > /home/user/uploads/file_beta.bin
    echo -n "image data" > /home/user/uploads/file_gamma.jpg

    # Create hashes.txt
    cat << 'EOF' > /home/user/hashes.txt
c782b143c08182245b0f49610530cc3c5f9498e6c41bbf7f43fb2b9d0344d9bc  file_alpha.txt
444d9359a35e07663e2621a62d04debd26dfb141ea89bc8e56b820dd3d52cb3e  file_beta.bin
7e7100b7fbba6165e3943d8ef4bf45c47df51755a5b6cbaaa7928b9cc65e3647  file_gamma.jpg
EOF

    # Create server_logs.json
    cat << 'EOF' > /home/user/server_logs.json
[
  {
    "ip": "192.168.1.10",
    "method": "POST",
    "path": "/upload",
    "headers": {"User-Agent": "Mozilla/5.0", "Cookie": "session=123"},
    "uploaded_file_id": "file_alpha.txt"
  },
  {
    "ip": "10.0.0.55",
    "method": "GET",
    "path": "/download?file=../../../etc/passwd",
    "headers": {"User-Agent": "curl/7.68.0", "Cookie": ""},
    "uploaded_file_id": null
  },
  {
    "ip": "192.168.1.11",
    "method": "POST",
    "path": "/upload",
    "headers": {"User-Agent": "Mozilla/5.0", "Cookie": "session=admin' OR 1=1"},
    "uploaded_file_id": "file_beta.bin"
  },
  {
    "ip": "172.16.0.4",
    "method": "GET",
    "path": "/index.php",
    "headers": {"User-Agent": "Mozilla/5.0 <script>alert(1)</script>", "Cookie": ""},
    "uploaded_file_id": null
  },
  {
    "ip": "192.168.1.12",
    "method": "POST",
    "path": "/upload",
    "headers": {"User-Agent": "Mozilla/5.0", "Cookie": "session=456"},
    "uploaded_file_id": "file_gamma.jpg"
  },
  {
    "ip": "10.0.0.55",
    "method": "GET",
    "path": "/assets/%2e%2e%2fconfig.yml",
    "headers": {"User-Agent": "curl/7.68.0"},
    "uploaded_file_id": null
  }
]
EOF

    chmod -R 777 /home/user
