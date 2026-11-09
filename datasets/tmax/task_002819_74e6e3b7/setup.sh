#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server gcc
    pip3 install --default-timeout=100 pytest redis numpy

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/sensor_sim.py
import socket
import struct
import time
import random
import sys

HOST = '127.0.0.1'
PORT = 8081

def generate_stream():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen(1)
    print(f"Sensor Simulator listening on {HOST}:{PORT}")

    conn, addr = s.accept()
    print(f"Connected by {addr}")

    try:
        # Base offset that causes catastrophic cancellation in naive variance
        base_offset = 100000.0

        for batch_idx in range(50):
            # Generate a batch of 100 readings
            readings = [base_offset + random.uniform(-1.0, 1.0) for _ in range(100)]

            # Occasionally insert a heartbeat
            if batch_idx % 5 == 0:
                conn.sendall(b'\x00\x00\xff\xff')

            # Send payload length (number of floats * 4 bytes)
            payload_len = len(readings) * 4
            conn.sendall(struct.pack('<H', payload_len))

            # Send floats
            for r in readings:
                conn.sendall(struct.pack('<f', r))

            time.sleep(0.05)

    except Exception as e:
        print(f"Sensor sim error: {e}")
    finally:
        conn.close()
        s.close()

if __name__ == '__main__':
    generate_stream()
EOF

    cat << 'EOF' > /home/user/app/variance.c
float compute_variance(float* data, int length) {
    if (length <= 1) return 0.0f;
    float sum = 0.0f;
    float sum_sq = 0.0f;
    for(int i=0; i<length; i++) {
        sum += data[i];
        sum_sq += data[i] * data[i];
    }
    return (sum_sq - (sum * sum)/length) / length;
}
EOF
    gcc -shared -fPIC -o /home/user/app/libvariance.so /home/user/app/variance.c
    rm /home/user/app/variance.c

    cat << 'EOF' > /home/user/app/aggregator.py
import socket
import struct
import ctypes
import redis
import time
import sys

HOST = '127.0.0.1'
PORT = 8081

# Load flawed C library
lib = ctypes.CDLL('/home/user/app/libvariance.so')
lib.compute_variance.argtypes = [ctypes.POINTER(ctypes.c_float), ctypes.c_int]
lib.compute_variance.restype = ctypes.c_float

r = redis.Redis(host='localhost', port=6379, db=0)

def run_aggregator():
    # Wait for sensor sim to start
    time.sleep(1)

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.connect((HOST, PORT))
    except Exception as e:
        print(f"Aggregator could not connect: {e}")
        return

    r.delete('batch_variances')

    while True:
        try:
            # Read payload length
            length_data = s.recv(2)
            if not length_data:
                break

            if len(length_data) < 2:
                continue

            payload_len = struct.unpack('<H', length_data)[0]

            # Read payload
            payload = b''
            while len(payload) < payload_len:
                chunk = s.recv(payload_len - len(payload))
                if not chunk:
                    break
                payload += chunk

            if len(payload) < payload_len:
                break

            num_floats = payload_len // 4
            floats = struct.unpack(f'<{num_floats}f', payload)

            # Calculate variance using flawed binary
            c_array = (ctypes.c_float * num_floats)(*floats)
            variance = lib.compute_variance(c_array, num_floats)

            r.rpush('batch_variances', float(variance))

        except Exception as e:
            print(f"Aggregator error: {e}")
            break

    s.close()

if __name__ == '__main__':
    run_aggregator()
EOF

    cat << 'EOF' > /home/user/app/run_e2e_test.py
import redis
import time
import sys

r = redis.Redis(host='localhost', port=6379, db=0)

def main():
    variances = r.lrange('batch_variances', 0, -1)
    if not variances:
        print("MSE: 999999.0")
        sys.exit(1)

    variances = [float(v) for v in variances]

    # Expected variance for uniform distribution U(-1, 1) is 1/3 ~ 0.3333...
    expected_variance = 1.0 / 3.0

    mse = sum((v - expected_variance)**2 for v in variances) / len(variances)
    print(f"MSE: {mse}")

if __name__ == '__main__':
    main()
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
service redis-server start
python3 /home/user/app/sensor_sim.py &
python3 /home/user/app/aggregator.py &
EOF
    chmod +x /home/user/app/start_services.sh

    chown -R user:user /home/user
    chmod -R 777 /home/user
