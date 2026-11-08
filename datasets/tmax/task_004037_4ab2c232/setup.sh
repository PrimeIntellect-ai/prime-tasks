#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc make
    pip3 install pytest flask fastapi uvicorn pillow pytesseract

    mkdir -p /app
    mkdir -p /home/user/clib

    # Generate the configuration image using Python and Pillow
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (300, 100), color='white')
d = ImageDraw.Draw(img)
d.text((10, 20), 'PORT=8282', fill='black')
d.text((10, 50), 'TOKEN=TRITON-77X-912', fill='black')
img.save('/app/server_config.png')
"

    # Create sorter.c
    cat << 'EOF' > /home/user/clib/sorter.c
void sort_array(int* arr, int len) {
    for(int i=0; i<len-1; i++) {
        for(int j=0; j<len-i-1; j++) {
            if(arr[j] > arr[j+1]) {
                int temp = arr[j];
                arr[j] = arr[j+1];
                arr[j+1] = temp;
            }
        }
    }
}
EOF

    # Create sorter.h
    cat << 'EOF' > /home/user/clib/sorter.h
void sort_array(int* arr, int len);
EOF

    # Create broken Makefile
    cat << 'EOF' > /home/user/clib/Makefile
all:
	gcc -o libsorter.so sorter.c
EOF

    # Create skeleton server.py
    cat << 'EOF' > /home/user/server.py
# TODO: Implement the server
# 1. Extract PORT and TOKEN from /app/server_config.png
# 2. Load libsorter.so using ctypes
# 3. Create a POST endpoint at /api/v1/process
# 4. Implement authentication using the TOKEN
# 5. Parse JSON, merge arrays, sort using C library, and return result

if __name__ == '__main__':
    pass
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
