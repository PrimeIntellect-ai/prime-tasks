#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/test_client.py
import socket
import time
import sys

def run_tests():
    log_file = open('/home/user/test_report.log', 'w')
    def log(msg):
        print(msg)
        log_file.write(msg + '\n')

    try:
        # Test 1: HELO and EXEC
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8888))
        s.sendall(b'HELO myclient\n')
        resp = s.recv(1024).decode()
        assert resp == 'ACK myclient\n', f"Expected ACK myclient\\n, got {resp!r}"

        s.sendall(b'EXEC status1\n')
        resp = s.recv(1024).decode()
        assert resp == 'RUN status1\n', f"Expected RUN status1\\n, got {resp!r}"
        s.sendall(b'QUIT\n')
        resp = s.recv(1024).decode()
        assert resp == 'BYE\n', f"Expected BYE\\n, got {resp!r}"
        s.close()

        # Test 2: Invalid State (EXEC before HELO)
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8888))
        s.sendall(b'EXEC cmd\n')
        resp = s.recv(1024).decode()
        assert resp == 'ERR 403 FORBIDDEN\n', f"Expected 403, got {resp!r}"
        s.close()

        # Test 3: Validation failure
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8888))
        s.sendall(b'HELO c\n')
        s.recv(1024)
        s.sendall(b'EXEC invalid-cmd!\n')
        resp = s.recv(1024).decode()
        assert resp == 'ERR 400 BAD REQUEST\n', f"Expected 400, got {resp!r}"
        s.close()

        # Test 4: Rate Limiting
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 8888))
        s.sendall(b'HELO rateclient\n')
        s.recv(1024)

        # 3 EXECs in quick succession
        s.sendall(b'EXEC a\n')
        resp1 = s.recv(1024).decode()
        s.sendall(b'EXEC b\n')
        resp2 = s.recv(1024).decode()
        s.sendall(b'EXEC c\n')
        resp3 = s.recv(1024).decode()

        assert resp1 == 'RUN a\n', f"R1 expected RUN a\\n, got {resp1!r}"
        assert resp2 == 'RUN b\n', f"R2 expected RUN b\\n, got {resp2!r}"
        assert resp3 == 'ERR 429 TOO MANY REQUESTS\n', f"R3 expected 429, got {resp3!r}"

        # Wait 1.1 seconds, next should pass
        time.sleep(1.1)
        s.sendall(b'EXEC d\n')
        resp4 = s.recv(1024).decode()
        assert resp4 == 'RUN d\n', f"R4 expected RUN d\\n, got {resp4!r}"

        s.sendall(b'QUIT\n')
        s.recv(1024)
        s.close()

        log("STATUS: ALL TESTS PASSED")
    except Exception as e:
        log(f"STATUS: FAILED - {str(e)}")
    finally:
        log_file.close()

if __name__ == '__main__':
    run_tests()
EOF

    chmod +x /home/user/test_client.py
    chmod -R 777 /home/user
