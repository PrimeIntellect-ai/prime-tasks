#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr bc
    pip3 install pytest Pillow

    mkdir -p /app

    # Create the oracle pipeline
    cat << 'EOF' > /app/oracle_pipeline.sh
#!/bin/bash
IFS=',' read -r id col2 col3 <<< "$1"

if [ -z "$col2" ] || [ "$col2" == "NaN" ]; then
    col2=15.5
fi

is_outlier=$(echo "$col3 > 100.0" | bc)
if [ "$is_outlier" -eq 1 ]; then
    col3=100.0
fi

score=$(echo "scale=4; ($col2 * 0.4) + ($col3 * 0.6)" | bc)
printf "%s,%s,%s,%.2f\n" "$id" "$col2" "$col3" "$score"
EOF
    chmod +x /app/oracle_pipeline.sh

    # Create the model parameters image
    python3 -c "
from PIL import Image, ImageDraw
img = Image.new('RGB', (500, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = 'Data Processing Parameters:\nImputation for Col2: 15.5\nOutlier Threshold Col3: 100.0\nWeights: W2=0.4, W3=0.6'
d.text((20, 20), text, fill=(0, 0, 0))
img.save('/app/model_params.png')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
