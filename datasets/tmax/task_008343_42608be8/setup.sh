#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logs

    cat << 'EOF' > /home/user/logs/gateway.log
[2023-11-01 02:59:58] INFO POST /api/v1/volatility TRACE_ID=req-11a2b 200 OK
[2023-11-01 02:59:59] INFO POST /api/v1/volatility TRACE_ID=req-33c4d 200 OK
[2023-11-01 03:00:00] ERROR POST /api/v1/volatility TRACE_ID=req-99z8x 500 Internal Server Error
[2023-11-01 03:00:01] INFO POST /api/v1/volatility TRACE_ID=req-55e6f 200 OK
EOF

    cat << 'EOF' > /home/user/logs/pricing.log
[2023-11-01 02:59:58] INFO req-11a2b Processing payload: {"prices": "100.5,101.2,102.0"}
[2023-11-01 02:59:59] INFO req-33c4d Processing payload: {"prices": "200.0,205.5,210.1"}
[2023-11-01 03:00:00] ERROR req-99z8x Processing payload: {"encoded_prices_b64": "MTAwMDAwMDAwMC4wMDAxLDEwMDAwMDAwMDAuMDAwMiwxMDAwMDAwMDAwLjAwMDM="}
[2023-11-01 03:00:01] INFO req-55e6f Processing payload: {"prices": "50.0,51.0,52.0"}
EOF

    cat << 'EOF' > /home/user/calc_volatility.py
import sys
import math

def calculate_volatility(prices):
    n = len(prices)
    if n < 2: return 0.0

    # Naive variance calculation
    sum_x = sum(prices)
    sum_x2 = sum(x*x for x in prices)

    variance = (sum_x2 - (sum_x * sum_x) / n) / (n - 1)

    # This will crash with a math domain error if variance < 0 due to float precision loss
    return math.sqrt(variance)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python calc_volatility.py <comma_separated_prices>")
        sys.exit(1)

    prices_str = sys.argv[1]
    prices = [float(x) for x in prices_str.split(',')]
    print(f"{calculate_volatility(prices):.6f}")
EOF
    chmod +x /home/user/calc_volatility.py

    chmod -R 777 /home/user
