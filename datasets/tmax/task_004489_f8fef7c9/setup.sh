#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest
    pip3 install --default-timeout=100 Pillow pytesseract python-dateutil

    mkdir -p /app

    # Generate the sensor label image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (500, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'FACTORY SENSOR AX-99\nCalibration Epoch: 2024-01-01T00:00:00Z\nMax RPM: 8450.5\nStatus: ACTIVE'
d.text((10,10), text, fill=(0,0,0))
img.save('/app/sensor_label.png')
"

    # Create the start_server.sh script
    cat << 'EOF' > /app/start_server.sh
#!/bin/bash
cd /app
mkdir -p data/clean data/evil

cat << 'JSON' > data/clean/1.json
{"timestamp": "2024-01-02T12:00:00Z", "rpm": 5000.0}
JSON
cat << 'JSON' > data/clean/2.json
{"timestamp": "2024-01-01T05:00:00+05:00", "rpm": 8450.5}
JSON
cat << 'JSON' > data/clean/3.json
{"timestamp": "2025-10-10T14:30:00-08:00", "rpm": 0.0}
JSON

cat << 'JSON' > data/evil/1.json
{"timestamp": "2023-12-31T23:59:59Z", "rpm": 5000.0}
JSON
cat << 'JSON' > data/evil/2.json
{"timestamp": "2024-05-05T12:00:00Z", "rpm": 8450.6}
JSON
cat << 'JSON' > data/evil/3.json
{"timestamp": "2024-01-01T01:00:00+02:00", "rpm": 1000.0}
JSON
cat << 'JSON' > data/evil/4.json
{"time": "2024-05-05T12:00:00Z", "rpm": 4000.0}
JSON
cat << 'JSON' > data/evil/5.json
{"timestamp": "invalid-time", "rpm": 4000.0}
JSON
cat << 'JSON' > data/evil/6.json
{"timestamp": "2024-05-05T12:00:00Z", "rpm": -10.0}
JSON

tar -czf data.tar.gz data
python3 -m http.server 8080
EOF
    chmod +x /app/start_server.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
