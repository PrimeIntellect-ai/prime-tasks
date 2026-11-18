#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx gcc curl
    pip3 install pytest flask requests

    mkdir -p /home/user/app/compute
    mkdir -p /home/user/app/gateway
    mkdir -p /home/user/app/corpora/clean
    mkdir -p /home/user/app/corpora/evil

    # Nginx skeleton config
    cat << 'EOF' > /etc/nginx/sites-available/math-app
server {
    listen 8080;
    server_name localhost;

    location / {
        # TODO: proxy to Gateway Service
    }
}
EOF

    # Start services script
    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
# TODO: set ENGINE_URL and start gateway and compute services
EOF
    chmod +x /home/user/app/start_services.sh

    # C library
    cat << 'EOF' > /home/user/app/compute/libpoly.c
double evaluate_polynomial(double* coefficients, int degree, double x) {
    double result = 0.0;
    double x_pow = 1.0;
    for (int i = 0; i <= degree; i++) {
        result += coefficients[i] * x_pow;
        x_pow *= x;
    }
    return result;
}
EOF

    # Compile C library
    gcc -shared -o /home/user/app/compute/libpoly.so -fPIC /home/user/app/compute/libpoly.c

    # Python stubs
    cat << 'EOF' > /home/user/app/compute/engine.py
# TODO: complete ctypes bindings and Flask route
EOF

    cat << 'EOF' > /home/user/app/gateway/sanitizer.py
# TODO: implement is_safe_payload
def is_safe_payload(json_payload: str) -> bool:
    pass
EOF

    cat << 'EOF' > /home/user/app/gateway/app.py
# TODO: implement Flask app and routes
EOF

    # Corpora
    for i in $(seq 1 50); do
        echo '{"type": "ast", "depth": 5, "matrix": {"dims": [50, 50]}}' > /home/user/app/corpora/clean/clean_$i.json
        echo '{"type": "ast", "depth": 15, "matrix": {"dims": [50, 50]}}' > /home/user/app/corpora/evil/evil_depth_$i.json
        echo '{"type": "ast", "depth": 5, "matrix": {"dims": [150, 50]}}' > /home/user/app/corpora/evil/evil_matrix_$i.json
    done

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
