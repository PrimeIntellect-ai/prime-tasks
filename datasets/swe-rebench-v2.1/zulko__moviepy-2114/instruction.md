KeyError: 'video_fps'

### Expected Behavior

No error should occur  as per docs

### Actual Behavior

> Traceback (most recent call last):
>   File "intro_prepare.py", line 10, in <module>
>
>   File "/Users/ishandutta2007/.pyenv/versions/3.5.0/lib/python3.5/site-packages/moviepy/video/io/VideoFileClip.py", line 91, in __init__
>     fps_source=fps_source)
>   File "/Users/ishandutta2007/.pyenv/versions/3.5.0/lib/python3.5/site-packages/moviepy/video/io/ffmpeg_reader.py", line 34, in __init__
>     self.fps = infos['video_fps']
> KeyError: 'video_fps'
>
>

### Steps to Reproduce the Problem
<!-- Please include code that demonstrates this problem so that we can reproduce it. For advice on how to do this, see https://stackoverflow.com/help/mcve -->

```
from moviepy.editor import *
from moviepy.video.io.ffmpeg_tools import ffmpeg_extract_subclip

from PIL import Image

ffmpeg_extract_subclip("./library/mySound_Effect.mp4", 6, 8.7, targetname="test.mp4")
intro_sound_vidio_clip = VideoFileClip('test.mp4')

```
### Specifications

  - Python Version: 3.5.0
  - Moviepy Version: 0.2.3.5
  - Platform Name: OSX 10.13
  - Platform Version: 10.13(High Sierra)

### Additional contract requirements

- When `ffmpeg_parse_infos` parses a file whose streams have no default stream marked, its result must contain the keys `default_video_stream_number`, `default_video_input_number`, `default_audio_stream_number`, `default_audio_input_number`, `video_fps`, and `audio_fps`.
