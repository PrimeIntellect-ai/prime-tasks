#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        fonts-dejavu-core

    pip3 install pytest pytesseract thefuzz python-Levenshtein

    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Create translation memory
    cat << 'EOF' > /home/user/translations.csv
string_id,en_text,es_text
1,Welcome,Bienvenido
2,Settings,Ajustes
3,Save changes,Guardar cambios
4,Profile,Perfil
5,Logout,Cerrar sesión
EOF

    # Generate test video (6 seconds)
    # 0-2s: Welcome
    # 2-4s: Settings
    # 4-5s: (blank)
    # 5-6s: Save changes
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=6 \
        -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Welcome':enable='between(t,0,2)':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2, \
             drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Settings':enable='between(t,2,4)':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2, \
             drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='Save changes':enable='between(t,5,6)':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=(h-text_h)/2" \
        -c:v libx264 -pix_fmt yuv420p /app/ui_walkthrough.mp4

    chmod -R 777 /home/user
    chmod -R 777 /app
