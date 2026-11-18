#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-liberation
    pip3 install pytest

    # Create directories
    mkdir -p /app/config /app/corpora/clean /app/corpora/evil

    # Generate the sensor specs image with the regex
    # The regex is: ^[A-Z]{3}-\d{4}(-[A-Z])?$
    # We need to escape the backslash for the shell if necessary, but in single quotes it's fine.
    # We will use a text file to avoid shell escaping issues with ImageMagick.
    echo "^[A-Z]{3}-\d{4}(-[A-Z])?$" > /tmp/regex.txt
    convert -size 800x200 xc:white -font Liberation-Sans -fill black -pointsize 36 -annotate +50+100 "@ /tmp/regex.txt" /app/config/sensor_specs.png

    # Create sample clean data
    cat << 'EOF' > /app/corpora/clean/data1.csv
timestamp,sensor_id,sensor_notes
2023-10-12T10:00:00Z,XYZ-9876,Normal operation
2023-10-12T10:05:00Z,ABC-1234-D,All systems go
EOF

    # Create sample evil data
    cat << 'EOF' > /app/corpora/evil/data1.csv
timestamp,sensor_id,sensor_notes
2023-10-12 10:00:00,XYZ-9876,Bad timestamp format
2023-10-12T10:05:00Z,ab-12,Invalid sensor ID
2023-10-12T10:10:00Z,ABC-1234,"Embedded
newline here"
2023-10-12T10:15:00Z,ABC-1234-D,Valid row should be preserved
EOF

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
