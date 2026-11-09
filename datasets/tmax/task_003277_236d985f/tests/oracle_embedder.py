import sys
import subprocess
import numpy as np

def main():
    video_path = sys.argv[1]
    N = int(sys.argv[2])
    target_str = sys.argv[3]
    target_emb = np.array([float(x) for x in target_str.split(',')], dtype=np.float32)

    cmd = ['ffmpeg', '-i', video_path, '-vframes', str(N), '-f', 'rawvideo', '-pix_fmt', 'gray', '-s', '64x64', 'pipe:1']
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    raw_bytes = result.stdout

    params = np.load('/app/model_params.npz')
    W = params['W']
    b = params['b']

    frames = np.frombuffer(raw_bytes, dtype=np.uint8).reshape(N, 4096).astype(np.float32) / 255.0
    embeddings = np.maximum(frames @ W + b, 0.0)

    best_idx = -1
    best_sim = -float('inf')

    target_norm = np.linalg.norm(target_emb)

    for i in range(N):
        emb = embeddings[i]
        norm = np.linalg.norm(emb)
        if norm == 0 or target_norm == 0:
            sim = 0.0
        else:
            sim = np.dot(emb, target_emb) / (norm * target_norm)

        if sim > best_sim:
            best_sim = sim
            best_idx = i

    print(f"{best_idx},{best_sim:.4f}")

if __name__ == '__main__':
    main()
