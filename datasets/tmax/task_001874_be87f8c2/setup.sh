#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ espeak ffmpeg
    pip3 install pytest SpeechRecognition pocketsphinx

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/dataset_note.wav "For the new experiment tracking, use an exponential moving average with an alpha of zero point eight."

    # Create the oracle program
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>

int main() {
    std::ios_base::sync_with_stdio(false);
    std::cin.tie(NULL);

    float alpha = 0.8f;
    float current_x;
    float previous_y = 0.0f;
    bool is_first = true;

    while (std::cin.read(reinterpret_cast<char*>(&current_x), sizeof(float))) {
        float y;
        if (is_first) {
            y = current_x;
            is_first = false;
        } else {
            y = alpha * current_x + (1.0f - alpha) * previous_y;
        }
        previous_y = y;
        std::cout.write(reinterpret_cast<const char*>(&y), sizeof(float));
    }
    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/oracle_ema
    rm /app/oracle.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
