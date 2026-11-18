#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tcpdump jq
pip3 install pytest

mkdir -p /home/user/app/data
cd /home/user/app

# 1. Create data files with spaces
echo "Data 1" > "data/file one.txt"
echo "Data 2" > "data/file two.txt"
echo "ERROR_TRIGGER" > "data/bad file.txt"

# 2. Create runner.sh (Buggy: breaks on spaces)
cat << 'EOF' > runner.sh
#!/bin/bash
# Buggy loop
for f in $(ls data/); do
    python3 worker.py "data/$f" &
done
wait
echo "All done"
EOF
chmod +x runner.sh

# 3. Create server.py (Buggy: Lock leak on error)
cat << 'EOF' > server.py
import socket
import threading
import time

stats_lock = threading.Lock()
processed_count = 0

def handle_client(conn, addr):
    global processed_count
    try:
        data = conn.recv(1024).decode('utf-8')
        stats_lock.acquire()
        if "ERROR_TRIGGER" in data:
            # BUG: Returns without releasing the lock
            conn.sendall(b"ERROR")
            conn.close()
            return

        processed_count += 1
        stats_lock.release()
        conn.sendall(b"OK")
    except Exception:
        pass
    finally:
        conn.close()

def start_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', 8888))
    server.listen(10)

    while True:
        try:
            conn, addr = server.accept()
            t = threading.Thread(target=handle_client, args=(conn, addr))
            t.daemon = True
            t.start()
        except KeyboardInterrupt:
            break

if __name__ == "__main__":
    start_server()
EOF

# 4. Create worker.py
cat << 'EOF' > worker.py
import sys
import socket

def send_file(filepath):
    try:
        with open(filepath, 'r') as f:
            data = f.read()

        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8888))
        s.sendall(data.encode('utf-8'))
        resp = s.recv(1024)
        s.close()
        print(f"Sent {filepath}, got {resp}")
    except Exception as e:
        print(f"Failed {filepath}: {e}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        send_file(sys.argv[1])
EOF

# 5. Create a fake pcap file
python3 -c "
import struct
import time

# Create a minimal pcap file with one packet showing destination port 8888
# Global header
pcap_global_header = struct.pack('<IHHIIII', 0xa1b2c3d4, 2, 4, 0, 0, 65535, 1)

# Packet data: Ethernet + IPv4 (localhost) + TCP (dst port 8888 = 0x22b8)
# Just raw bytes for a simple SYN packet to port 8888
packet_data = bytes.fromhex('00000000000000000000000008004500003c1c464000400600007f0000017f000001a1f622b8e3a1000000000000a002faf0000000000204ffd70402080a000000000000000001030307')
ts_sec = int(time.time())
ts_usec = 0
incl_len = len(packet_data)
orig_len = len(packet_data)

pcap_packet_header = struct.pack('<IIII', ts_sec, ts_usec, incl_len, orig_len)

with open('capture.pcap', 'wb') as f:
    f.write(pcap_global_header)
    f.write(pcap_packet_header)
    f.write(packet_data)
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
