import sys
import cv2
import struct

def process_video(input_path, output_path):
    cap = cv2.VideoCapture(input_path)
    intensities = []

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        intensities.append(frame.mean())

    with open(output_path, 'wb') as f:
        f.write(struct.pack('<I', len(intensities)))
        for intensity in intensities:
            f.write(struct.pack('<f', intensity))

    cap.release()

if __name__ == "__main__":
    process_video(sys.argv[1], sys.argv[2])
