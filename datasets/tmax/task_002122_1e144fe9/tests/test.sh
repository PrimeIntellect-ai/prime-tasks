#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont

CPP_FILE = "/home/user/resolve_network.cpp"
IMAGE_FILE = "/app/network_params.png"
TESSERACT = "/usr/bin/tesseract"
REAL_TESSERACT = "/usr/bin/tesseract.verifier-real"
TESSERACT_LOG = "/tmp/tesseract-verifier.log"
FLOAT_RE = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?")


def expected_kl(edges, alpha):
    n = max(max(a, b) for a, b in edges) + 1
    outgoing = [[] for _ in range(n)]
    for a, b in edges:
        outgoing[a].append(b)

    p = [[0.0] * n for _ in range(n)]
    for i in range(n):
        if outgoing[i]:
            weight = 1.0 / len(outgoing[i])
            for j in outgoing[i]:
                p[i][j] += weight
        else:
            p[i][i] = 1.0

    m = [
        [(1.0 - alpha) * p[i][j] + alpha / n for j in range(n)]
        for i in range(n)
    ]
    pi = [1.0 / n] * n
    for _ in range(200000):
        nxt = [sum(pi[i] * m[i][j] for i in range(n)) for j in range(n)]
        if max(abs(nxt[i] - pi[i]) for i in range(n)) < 1e-14:
            pi = nxt
            break
        pi = nxt
    total = sum(pi)
    pi = [x / total for x in pi]
    return sum(x * math.log(x / (1.0 / n)) for x in pi if x > 0.0)


def render_image(edges, alpha):
    image = Image.new("RGB", (400, 300), color=(255, 255, 255))
    draw = ImageDraw.Draw(image)
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf", 24
        )
    except OSError:
        font = ImageFont.load_default()
    lines = ["Edges:"] + [f"{a} {b}" for a, b in edges] + [f"Alpha: {alpha:.2f}"]
    draw.text((10, 10), "\n".join(lines), font=font, fill=(0, 0, 0))
    image.save(IMAGE_FILE)


def run_and_check(exe_path, edges, alpha, label):
    before = os.path.getsize(TESSERACT_LOG) if os.path.exists(TESSERACT_LOG) else 0
    with tempfile.TemporaryDirectory(prefix="resolve-network-") as cwd:
        result = subprocess.run(
            [exe_path], cwd=cwd, capture_output=True, text=True, timeout=30
        )
    assert result.returncode == 0, f"Execution failed for {label}:\n{result.stderr}"
    output = result.stdout.strip()
    assert FLOAT_RE.fullmatch(output), (
        f"Program must print only one finite floating-point number for {label}; "
        f"stdout was: {result.stdout!r}"
    )
    value = float(output)
    assert math.isfinite(value), f"Non-finite output for {label}: {output}"

    after = os.path.getsize(TESSERACT_LOG) if os.path.exists(TESSERACT_LOG) else 0
    assert after > before, f"Program did not invoke tesseract while processing {label}."

    expected = expected_kl(edges, alpha)
    error = abs(value - expected)
    threshold = 0.05
    assert error <= threshold, (
        f"KL divergence error {error:.5f} exceeds threshold {threshold} for {label}. "
        f"Expected approximately {expected:.5f}, but program output {value}."
    )


def test_resolve_network_output():
    assert os.path.isfile(CPP_FILE), f"Required file {CPP_FILE} does not exist."

    with open(CPP_FILE, "r", encoding="utf-8", errors="replace") as source_file:
        source = source_file.read()
    assert "tesseract" in source.lower(), "The program must use tesseract to read the image."

    exe_path = "/tmp/resolve_network"
    compile_result = subprocess.run(
        ["g++", CPP_FILE, "-o", exe_path], capture_output=True, text=True
    )
    assert compile_result.returncode == 0, f"Compilation failed:\n{compile_result.stderr}"

    original_image = open(IMAGE_FILE, "rb").read()
    assert os.path.exists(TESSERACT), "tesseract executable is missing"
    if os.path.exists(REAL_TESSERACT):
        os.remove(REAL_TESSERACT)
    os.rename(TESSERACT, REAL_TESSERACT)
    with open(TESSERACT, "w", encoding="utf-8") as wrapper:
        wrapper.write(
            "#!/bin/sh\n"
            f"echo invoked >> {TESSERACT_LOG}\n"
            f"exec {REAL_TESSERACT} \"$@\"\n"
        )
    os.chmod(TESSERACT, 0o755)
    if os.path.exists(TESSERACT_LOG):
        os.remove(TESSERACT_LOG)

    original_edges = [(0, 1), (1, 2), (2, 0), (2, 3), (3, 3)]
    rng = random.SystemRandom()
    n = rng.randint(5, 8)
    cycle_edges = [(i, (i + 1) % n) for i in range(n)]
    sink_edges = [(0, 0)] + [(i, 0) for i in range(1, n)]
    low_alpha = rng.choice([0.03, 0.04, 0.06, 0.07, 0.09])
    high_alpha = rng.choice([0.55, 0.61, 0.68, 0.74])

    random_edges = []
    for i in range(n):
        random_edges.append((i, rng.randrange(n)))
    for _ in range(n // 2 + 1):
        edge = (rng.randrange(n), rng.randrange(n))
        if edge not in random_edges:
            random_edges.append(edge)

    try:
        # Preserve the original verifier's check on the supplied image.
        run_and_check(exe_path, original_edges, 0.15, "the original image")

        # Fresh images prevent a precomputed constant from satisfying the task.
        cases = [
            (cycle_edges, low_alpha, "a generated cycle graph"),
            (sink_edges, low_alpha, "a generated sink graph with low Alpha"),
            (sink_edges, high_alpha, "the same sink graph with a different Alpha"),
            (random_edges, low_alpha, "a generated random graph"),
        ]
        for edges, alpha, label in cases:
            render_image(edges, alpha)
            run_and_check(exe_path, edges, alpha, label)
    finally:
        with open(IMAGE_FILE, "wb") as image_file:
            image_file.write(original_image)
        if os.path.exists(TESSERACT):
            os.remove(TESSERACT)
        if os.path.exists(REAL_TESSERACT):
            os.rename(REAL_TESSERACT, TESSERACT)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
