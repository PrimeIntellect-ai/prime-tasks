#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gawk
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create staging directories
    mkdir -p /home/user/doc_staging/project_alpha/v1
    mkdir -p /home/user/doc_staging/project_beta/drafts
    mkdir -p /home/user/doc_staging/shared_assets/printing

    # Create Markdown files
    cat << 'EOF' > /home/user/doc_staging/project_alpha/v1/intro.md
---
title: Introduction to Alpha
status: final
---
This is the intro.
EOF

    cat << 'EOF' > /home/user/doc_staging/project_alpha/v1/spec.md
---
title: Technical Specifications
status: draft
---
Draft specs here.
EOF

    cat << 'EOF' > /home/user/doc_staging/project_beta/drafts/notes.md
---
title: Beta Notes
status: final
---
These are final notes.
EOF

    # Create GCode files
    cat << 'EOF' > /home/user/doc_staging/project_alpha/v1/housing.gcode
; FLAVOR:Marlin
; TIME:3600
; MATERIAL: ABS
G28
G1 X10 Y10
EOF

    cat << 'EOF' > /home/user/doc_staging/shared_assets/printing/gear.gcode
; FLAVOR:Marlin
; TIME:1200
; MATERIAL: PLA
G28
G1 X20 Y20
EOF

    cat << 'EOF' > /home/user/doc_staging/shared_assets/printing/test_cube.gcode
; FLAVOR:Marlin
; TIME:600
G28
EOF

    chmod -R 777 /home/user
