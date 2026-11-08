#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip tesseract-ocr gcc make patch
pip3 install pytest numpy Pillow

mkdir -p /app
cat << 'EOF' > /tmp/make_image.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "Target Polynomial: f(x) = 2.5*x^3 - 1.2*x^2 + 0.5*x - 3.1\n Minimum Build Core: >= 1.4.0"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/spec.png')
EOF
python3 /tmp/make_image.py
rm /tmp/make_image.py

mkdir -p /home/user/math_module

cat << 'EOF' > /home/user/math_module/version.txt
1.5.2
EOF

cat << 'EOF' > /home/user/math_module/mathops.c
#include <stddef.h>
void compute_poly(const float* input, float* output, int size) {
    for(int i = 0; i < size; i++) {
        float x = input[i];
        // Agent needs to update this formula
        output[i] = x; 
    }
}
EOF

cat << 'EOF' > /home/user/math_module/fast_math.patch
--- mathops.c
+++ mathops.c
@@ -3,6 +3,7 @@
     for(int i = 0; i < size; i++) {
         float x = input[i];
-        output[i] = x;
+        // unrolled loop or optimization marker
+        output[i] = x; // placeholder for agent to fix
     }
 }
EOF

cat << 'EOF' > /home/user/math_module/Makefile
libmathops.so: mathops.c
	gcc mathops.c -o libmathops.so
EOF

useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
