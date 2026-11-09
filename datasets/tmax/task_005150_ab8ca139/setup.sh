#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest numpy pandas scipy pillow matplotlib pytesseract

    mkdir -p /app
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (800, 200), color = (255, 255, 255))
d = ImageDraw.Draw(img)
text = 'System: Van der Pol Oscillator\nParameter mu = 1000\nInitial conditions: y0 = [2.0, 0.0]\nTime span: t = [0, 3000]\nOutput shape: 3000 evenly spaced points.'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/equation_params.png')
"

    mkdir -p /home/user
    cat << 'EOF' > /home/user/generate_data.py
import numpy as np
import pandas as pd
from scipy.integrate import solve_ivp

# TODO: Update parameters from image
mu = 1.0 
t_span = (0, 20)
y0 = [1.0, 1.0]
n_points = 100

def vdp_derivatives(t, y):
    y1, y2 = y
    dy1 = y2
    dy2 = mu * (1 - y1**2) * y2 - y1
    return [dy1, dy2]

t_eval = np.linspace(t_span[0], t_span[1], n_points)

# Flawed integration: RK45 will struggle/diverge for high mu
sol = solve_ivp(vdp_derivatives, t_span, y0, method='RK45', t_eval=t_eval)

df = pd.DataFrame({
    't': sol.t,
    'y1': sol.y[0],
    'y2': sol.y[1]
})
df.to_csv('/home/user/training_data.csv', index=False)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
