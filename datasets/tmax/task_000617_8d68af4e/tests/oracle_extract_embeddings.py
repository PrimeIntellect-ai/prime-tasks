#!/usr/bin/env python3
import sys
import cv2
import numpy as np

def main():
    if len(sys.argv) < 2:
        sys.exit(1)

    try:
        frame_idx = int(sys.argv[1])
    except ValueError:
        print(",".join(["0.0000"] * 16))
        return

    cap = cv2.VideoCapture('/app/experiment_record.mp4')

    # Check bounds
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    if frame_idx < 0 or frame_idx >= total_frames:
        print(",".join(["0.0000"] * 16))
        return

    cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
    ret, frame = cap.read()

    if not ret:
        print(",".join(["0.0000"] * 16))
        return

    patch = frame[0:32, 0:32, :]
    vec = patch.flatten().astype(np.float64) / 255.0

    weights = np.load('/home/user/model_weights.npz')
    W = weights['W']
    b = weights['b']

    z = np.dot(vec, W) + b
    emb = np.maximum(0, z)

    output = ",".join([f"{v:.4f}" for v in emb])
    print(output)

if __name__ == '__main__':
    main()
