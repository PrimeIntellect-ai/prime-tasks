#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-venv ffmpeg
    pip3 install pytest

    mkdir -p /app
    # Generate the video fixture with a 12Hz flashing square in the top-left 100x100 pixels
    ffmpeg -y -f lavfi -i "color=c=black:s=640x480:r=60:d=10" \
        -vf "geq=r='if(lt(X,100)*lt(Y,100), 255*(0.5+0.5*sin(2*PI*12*T)), 0)':g='if(lt(X,100)*lt(Y,100), 255*(0.5+0.5*sin(2*PI*12*T)), 0)':b='if(lt(X,100)*lt(Y,100), 255*(0.5+0.5*sin(2*PI*12*T)), 0)'" \
        -c:v libx264 /app/ui_render_test.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
