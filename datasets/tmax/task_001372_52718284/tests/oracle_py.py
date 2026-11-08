import sys
import subprocess
import json

def get_frame(frame_num):
    cmd = [
        'ffmpeg', '-y', '-i', '/app/video.mp4', '-vf', f'select=eq(n\\,{frame_num})',
        '-vframes', '1', '-f', 'image2pipe', '-vcodec', 'pgm', '-'
    ]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate()
    return out

def count_bright(pgm_data):
    if not pgm_data: return 0
    parts = pgm_data.split(b'\n', 3)
    if len(parts) < 4: return 0
    idx = pgm_data.find(b'255\n')
    if idx == -1: return 0
    pixels = pgm_data[idx+4:]
    return sum(1 for b in pixels if b > 128)

if __name__ == '__main__':
    frame_num = int(sys.argv[1])
    raw_frame = get_frame(frame_num)
    brights = count_bright(raw_frame)
    print(json.dumps({"frame": frame_num, "bright_pixels": brights}))
