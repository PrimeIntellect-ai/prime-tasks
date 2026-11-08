#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        python3-numpy \
        python3-scipy \
        cmake \
        build-essential \
        curl \
        libsndfile1-dev

    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user/audio_pr/src
    mkdir -p /home/user/audio_pr/api/cgi-bin

    cat << 'EOF' > /home/user/audio_pr/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(audio-envelope-api C)

set(CMAKE_C_VISIBILITY_PRESET hidden)

add_library(envelope SHARED src/envelope.c)
target_link_libraries(envelope sndfile m)

add_executable(envelope_cli src/cli.c)
# Missing target_link_libraries(envelope_cli envelope)
EOF

    cat << 'EOF' > /home/user/audio_pr/src/envelope.c
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <sndfile.h>

// Missing visibility attribute
float* compute_envelope(const char* filepath, int* out_length) {
    SF_INFO sfinfo;
    SNDFILE* infile = sf_open(filepath, SFM_READ, &sfinfo);
    if (!infile) return NULL;

    int window_size = sfinfo.samplerate * 0.1; // 100ms
    int num_windows = sfinfo.frames / window_size;
    *out_length = num_windows;

    float* env = malloc(num_windows * sizeof(float));
    float* buffer = malloc(window_size * sizeof(float));

    for (int i = 0; i < num_windows; i++) {
        sf_read_float(infile, buffer, window_size);
        float sum = 0;
        for (int j = 0; j < window_size; j++) {
            sum += buffer[j] * buffer[j];
        }
        env[i] = sqrt(sum / window_size);
    }

    free(buffer);
    sf_close(infile);
    return env;
}
EOF

    cat << 'EOF' > /home/user/audio_pr/src/cli.c
#include <stdio.h>
#include <stdlib.h>

float* compute_envelope(const char* filepath, int* out_length);

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    int len = 0;
    float* env = compute_envelope(argv[1], &len);
    if (!env) return 1;
    printf("[");
    for (int i = 0; i < len; i++) {
        printf("%f%s", env[i], i == len - 1 ? "" : ", ");
    }
    printf("]\n");
    free(env);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/audio_pr/api/server.sh
#!/bin/bash
python3 -m http.server --cgi 8080
EOF
    chmod +x /home/user/audio_pr/api/server.sh

    cat << 'EOF' > /home/user/audio_pr/api/cgi-bin/process.sh
#!/bin/bash
echo "Content-type: application/json"
echo ""
cat > /tmp/req.wav
envelope_cli /tmp/req.wav
EOF
    chmod +x /home/user/audio_pr/api/cgi-bin/process.sh

    cat << 'EOF' > /tmp/generate_audio.py
import numpy as np
from scipy.io import wavfile
import json

fs = 44100
t = np.linspace(0, 1, fs, endpoint=False)
audio = 0.5 * np.sin(2 * np.pi * 440 * t) + 0.1 * np.random.randn(fs)
wavfile.write("/app/test_audio.wav", fs, audio.astype(np.float32))

window_size = int(fs * 0.1)
num_windows = len(audio) // window_size
env = []
for i in range(num_windows):
    chunk = audio[i*window_size:(i+1)*window_size]
    env.append(float(np.sqrt(np.mean(chunk**2))))

with open("/root/reference_envelope.json", "w") as f:
    json.dump(env, f)
EOF
    python3 /tmp/generate_audio.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
