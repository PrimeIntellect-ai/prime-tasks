#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg python3-pil
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os
import random
import subprocess
from PIL import Image

# Generate video
os.makedirs('/tmp/frames', exist_ok=True)
frames = ['red'] * 42 + ['blue'] * 258
random.shuffle(frames)

for i, color in enumerate(frames):
    img = Image.new('RGB', (64, 64), color=color)
    img.save(f'/tmp/frames/frame_{i:04d}.png')

subprocess.run(['ffmpeg', '-framerate', '30', '-i', '/tmp/frames/frame_%04d.png', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/app/legacy_tests.mp4'], check=True)

# Generate clean corpus
clean_code = [
    'print "Hello"',
    'for i in xrange(10): pass',
    'd.iteritems()',
    'x = 1 + 2',
    'print "test %s" % "a"',
    'y = xrange(5)',
    'print "foo"',
    'a = 10',
    'b = 20',
    'print a + b',
    'for x in xrange(2): print x',
    'd = {"a": 1}; d.iterkeys()',
    'd.itervalues()',
    'print "a", "b"',
    'x = xrange(100)',
    'print "done"',
    'a = 1',
    'b = 2',
    'c = 3',
    'print c'
]

for i, code in enumerate(clean_code):
    with open(f'/app/corpus/clean/clean_{i:02d}.py', 'w') as f:
        f.write(code)

# Generate evil corpus
evil_code = [
    '__import__("os").system("echo evil")',
    'eval("1+1")',
    'exec("a=1")',
    '[__import__("os").system("ls") for i in range(1)]',
    'open("/etc/passwd").read()',
    'import os; os.system("id")',
    'eval("__import__(\'os\').system(\'ls\')")',
    'exec("import os; os.system(\'ls\')")',
    '__builtins__["eval"]("1")',
    'getattr(__builtins__, "eval")("1")',
    '__import__("subprocess").call(["ls"])',
    'import subprocess; subprocess.Popen(["ls"])',
    '__import__("sys").modules["os"].system("ls")',
    'eval(compile("print(\'evil\')", "<string>", "exec"))',
    'exec(compile("print(\'evil\')", "<string>", "exec"))',
    '__import__("pty").spawn("/bin/bash")',
    'import pty; pty.spawn("/bin/sh")',
    '__import__("os").popen("ls").read()',
    'import os; os.popen("ls").read()',
    '__import__("os").spawnlp(__import__("os").P_WAIT, "ls")'
]

for i, code in enumerate(evil_code):
    with open(f'/app/corpus/evil/evil_{i:02d}.py', 'w') as f:
        f.write(code)
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/frames /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
