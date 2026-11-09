#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest numpy Pillow psutil requests

    mkdir -p /home/user
    mkdir -p /app

    # Create dummy reference image
    python3 -c "from PIL import Image; Image.new('RGB', (100, 100), color='red').save('/app/reference_sample.png')"

    # Create image_service.py
    cat << 'EOF' > /home/user/image_service.py
import json
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
import numpy as np
from PIL import Image

history = []
temp_matrix = None

class RequestHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        global history, temp_matrix

        # Memory leak: appending large arrays
        history.append(np.zeros((1000, 1000)))

        # Race condition: shared global state without lock
        temp_matrix = np.random.rand(100, 100)

        try:
            # Simulate SVD
            u, s, vh = np.linalg.svd(temp_matrix)
            signature = s.tolist()

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'signature': signature[:10]}).encode())
        except Exception as e:
            self.send_response(500)
            self.end_headers()

class ThreadedHTTPServer(HTTPServer):
    def process_request(self, request, client_address):
        thread = threading.Thread(target=self.__new_request, args=(self.RequestHandlerClass, request, client_address))
        thread.start()

    def __new_request(self, handlerClass, request, address):
        self.finish_request(request, address)
        self.shutdown_request(request)

if __name__ == '__main__':
    server = ThreadedHTTPServer(('0.0.0.0', 8080), RequestHandler)
    server.serve_forever()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
