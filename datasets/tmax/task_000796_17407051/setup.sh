#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest numpy scipy

useradd -m -s /bin/bash user || true

mkdir -p /app
mkdir -p /tests/corpora

python3 -c "
import numpy as np
from scipy.io import wavfile
sample_rate = 44100
t = np.linspace(0, 1, sample_rate)
audio = (np.sin(2 * np.pi * 440 * t) * 10000).astype(np.int16)
wavfile.write('/app/reference_audio.wav', sample_rate, audio)
"

cat << 'EOF' > /home/user/wave_math.py
import sys
from scipy.io import wavfile
import math

def main():
    if len(sys.argv) != 4:
        print("Usage: python wave_math.py <input_wav> <output_wav> '<expression>'")
        sys.exit(1)

    input_wav = sys.argv[1]
    output_wav = sys.argv[2]
    expression = sys.argv[3]

    sample_rate, data = wavfile.read(input_wav)

    new_data = []
    for x in data:
        # Vulnerable eval
        new_data.append(eval(expression))

    import numpy as np
    wavfile.write(output_wav, sample_rate, np.array(new_data, dtype=np.int16))

if __name__ == "__main__":
    main()
EOF

cat << 'EOF' > /tests/corpora/evil_expressions.txt
__import__("os").system("rm -rf /")
exec("import sys")
[x for x in ().__class__.__base__.__subclasses__() if x.__name__ == "catch_warnings"][0]()._module.__builtins__["__import__"]("os").system("ls")
EOF

cat << 'EOF' > /tests/corpora/clean_expressions.txt
x * 0.5
sin(x)
x**2 + cos(x)
x / 2.0
EOF

chmod -R 777 /home/user
chmod -R 777 /app
chmod -R 777 /tests
