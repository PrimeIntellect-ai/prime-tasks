#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app/research_data

    # Generate the audio file
    espeak -w /app/research_data/interview_sample.wav "the patient exhibits mild symptoms"

    # Create index.csv
    cat << 'EOF' > /app/research_data/index.csv
filename,participant_id,date
interview_sample.wav,P-8842,2023-10-12
other_file.wav,P-1122,2023-10-11
EOF

    # Create metadata.xml
    cat << 'EOF' > /app/research_data/metadata.xml
<records>
    <record>
        <file>other_file.wav</file>
        <location>Clinic A</location>
    </record>
    <record>
        <file>interview_sample.wav</file>
        <location>Clinic B</location>
    </record>
</records>
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
