Changes in FFmpeg libavformat break FFmpegInfosParser
#### Expected Behavior
`FFmpegInfosParser.parse` can parse FFmpeg output.

#### Actual Behavior
`FFmpegInfosParser.parse` fails to parse FFmpeg output starting with commit [b7251ae](https://github.com/FFmpeg/FFmpeg/commit/b7251aed46f5ac96fe65c1c68ddac44b07429467), which reduced indentation for streams.

#### Steps to Reproduce the Problem
Point MoviePy to FFmpeg executable with the mentioned revision or newer and run `FFmpegInfosParser.parse`.

#### Specifications
- Python Version: 3.9.9
- Moviepy Version: 2.0.0.dev2 8eaf3f0
- Platform Name: Linux
- Platform Version: Fedora 34

#### Additional Info
ffmpeg 4.2.2 (imageio) output:
```
Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'clip.mp4':
  Metadata:
    major_brand     : isom
    minor_version   : 512
    compatible_brands: isomiso2avc1mp41
    encoder         : Lavf58.12.100
  Duration: 01:00:00.00, start: 0.000000, bitrate: 1222 kb/s
    Stream #0:0(und): Video: h264 (Main) (avc1 / 0x31637661), yuv420p, 1280x720 [SAR 1:1 DAR 16:9], 1221 kb/s, 25 fps, 25 tbr, 12800 tbn, 50 tbc (default)
    Metadata:
      handler_name    : VideoHandler
At least one output file must be specified
```
ffmpeg 4.4.1 (system) output:
```
Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'clip.mp4':
  Metadata:
    major_brand     : isom
    minor_version   : 512
    compatible_brands: isomiso2avc1mp41
    encoder         : Lavf58.12.100
  Duration: 01:00:00.00, start: 0.000000, bitrate: 1222 kb/s
  Stream #0:0(und): Video: h264 (Main) (avc1 / 0x31637661), yuv420p, 1280x720 [SAR 1:1 DAR 16:9], 1221 kb/s, 25 fps, 25 tbr, 12800 tbn, 50 tbc (default)
    Metadata:
      handler_name    : VideoHandler
      vendor_id       : [0][0][0][0]
At least one output file must be specified
```
There are other commits changing the output format too, but the mentioned one is the most problematic one.
