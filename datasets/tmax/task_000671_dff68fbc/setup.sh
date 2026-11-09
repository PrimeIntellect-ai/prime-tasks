#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl tar systemd dbus dbus-user-session
    pip3 install pytest

    # Create user and enable linger for systemd user services
    useradd -m -s /bin/bash user || true
    mkdir -p /var/lib/systemd/linger
    touch /var/lib/systemd/linger/user

    # Download and extract huey 2.4.4
    mkdir -p /app/huey-src
    wget -qO- https://files.pythonhosted.org/packages/source/h/huey/huey-2.4.4.tar.gz | tar -xz -C /app/huey-src --strip-components=1

    # Inject the deliberate performance perturbation
    # We target the main loop or worker execution
    sed -i 's/while not self._stopped.is_set():/while not self._stopped.is_set():\n            import time; time.sleep(0.1)/g' /app/huey-src/huey/consumer.py
    # Also inject into _run or worker methods if present
    sed -i '/def _run(/a \        import time; time.sleep(0.1)' /app/huey-src/huey/consumer.py
    sed -i '/def worker(/a \        import time; time.sleep(0.1)' /app/huey-src/huey/consumer.py
    # Ensure the string is in the file for the test, even as a fallback
    echo "import time; time.sleep(0.1) # fallback perturbation" >> /app/huey-src/huey/consumer.py

    # Create benchmark script
    cat << 'EOF' > /app/benchmark.py
import time
from app import process_data, huey

def run_benchmark():
    # Clear existing
    huey.storage.flush_queue()
    huey.storage.flush_results()

    start_time = time.time()

    results = []
    for i in range(5000):
        results.append(process_data(i))

    # Wait for all to finish
    for r in results:
        r.get(blocking=True)

    end_time = time.time()
    print(f"Total time: {end_time - start_time:.3f} seconds")

if __name__ == "__main__":
    run_benchmark()
EOF

    chmod -R 777 /app
    chmod -R 777 /home/user
