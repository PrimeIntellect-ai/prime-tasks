#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/locales

    cat << 'EOF' > /home/user/locales/en.json
[
  {"id": 1, "start": "00:00:10.000", "end": "00:00:15.500", "text": "Let $x^2 + y^2 = r^2$ be the circle."},
  {"id": 2, "start": "00:00:16.000", "end": "00:00:20.000", "text": "The derivative is \\frac{dy}{dx} = -\\frac{x}{y}."}
]
EOF

    cat << 'EOF' > /home/user/locales/es.xml
<?xml version="1.0" encoding="UTF-8"?>
<subs>
  <sub id="1" start="10.000" end="15.500"><text>Sea $x^2 + y^2 = r^2$ el circulo.</text></sub>
  <sub id="2" start="16.000" end="20.000"><text>La derivada es \frac{dy}{dx} = -\frac{x}{y}.</text></sub>
</subs>
EOF

    cat << 'EOF' > /home/user/locales/fr.csv
id,start,end,text
1,00:00:10.000,00:00:15.500,Soit $x^2 + y^2 = r^2$ le cercle.
2,00:00:16.000,00:00:20.000,La derivee est \frac{dy}{dx} = -\frac{x}{y}.
EOF

    chmod -R 777 /home/user
