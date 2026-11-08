A second loadSource call autoplays primary content immediately.
### What version of Hls.js are you using?

v1.6.0-beta

### What browser (including version) are you using?

Chrome

### What OS (including version) are you using?

macOS

### Test stream

_No response_

### Configuration

```JavaScript
{}
```


### Additional player setup steps

This is a regression compared to v1.5.

A sample with v1.5: https://stackblitz.com/edit/vitejs-vite-fkf2xf
A sample with v1.6-beta: https://stackblitz.com/edit/vitejs-vite-tohum2

The same steps to reproduce result in different behavior, with v1.5 not starting the asset (as it requires a user gesture), but v1.6 does.

### Checklist

- [X] The issue observed is not already reported by searching on Github under https://github.com/video-dev/hls.js/issues
- [X] The issue occurs in the stable client (latest release) on https://hlsjs.video-dev.org/demo and not just on my page
- [X] The issue occurs in the latest client (main branch) on https://hlsjs-dev.video-dev.org/demo and not just on my page
- [X] The stream has correct Access-Control-Allow-Origin headers (CORS)
- [X] There are no network errors such as 404s in the browser console when trying to play the stream

### Steps to reproduce

1. Click "loadSource".
2. Click "play".
3. Click "loadSource" again, and you'll notice that playback starts immediately.


### Expected behaviour

A subsequent loadSource call should not start playback when no `autoplay` attribute is present.

### What actually happened?

A subsequent loadSource call starts playback immediately, with `autoplay` not present on the video element.

### Console output

```shell
N/A
```


### Chrome media internals output

_No response_
Duplicate initial request on the manifest file (m3u8) when playing a live stream
### What version of Hls.js are you using?

v1.5.17

### What browser (including version) are you using?

Edge 130 64 bits

### What OS (including version) are you using?

Windows 11

### Test stream

https://1600654994.rsc.cdn77.org/streaming-rtmp/ubicasttv/ovh_ubicasttv_d47167f23a35894c5e89c40f835431_720.m3u8

### Configuration

```JavaScript
{
  "debug": true,
  "enableWorker": true,
  "lowLatencyMode": true,
  "backBufferLength": 90
}
```


### Additional player setup steps

_No response_

### Checklist

- [X] The issue observed is not already reported by searching on Github under https://github.com/video-dev/hls.js/issues
- [X] The issue occurs in the stable client (latest release) on https://hlsjs.video-dev.org/demo and not just on my page
- [X] The issue occurs in the latest client (main branch) on https://hlsjs-dev.video-dev.org/demo and not just on my page
- [X] The stream has correct Access-Control-Allow-Origin headers (CORS)
- [X] There are no network errors such as 404s in the browser console when trying to play the stream

### Steps to reproduce

1. Go on the test page.
2. Open the network console and clear it.
3. Set the stream URL with the one given in this ticket (I suppose the problem occurs with all m3u8).

### Expected behaviour

The first request to get the m3u8 is not made twice.

### What actually happened?

The first request to get the m3u8 is made twice.

The problem also occurs with:
- Firefox 132 64 bits linux (Debian 12)
- Chromium 130 64 bits linux (Debian 12)

We discovered this problem because we have a mechanism that blocks simultaneous duplicate requests on our site.

Screenshot of the network console:

- Edge:
![Edge_2024-11-21 09-52-52](https://github.com/user-attachments/assets/0321357a-ae1e-408f-a6d5-d15d052a6026)
- Firefox:
![FF_2024-11-21 09-43-27](https://github.com/user-attachments/assets/9e6e11cb-3261-44a4-8e25-e760f60b7535)


### Console output

```shell
09:57:26,705 [log] > [stream-controller]: Parsed main sn: 4411 of level 0 (frag:[0.000-3.051]) base-stream-controller.ts:1955:9
09:57:26,834 [log] > [stream-controller]: Buffered main sn: 4411 of level 0 (frag:[0.000-3.051] > buffer:[0.052-2.995]) base-stream-controller.ts:713:9
09:57:26,834 [log] > [stream-controller]: PARSED->IDLE base-stream-controller.ts:2008:11
09:57:26,834 [log] > [stream-controller]: adjusting start position by 0.04624399999999977 to match buffer start stream-controller.ts:1138:13
09:57:26,834 [log] > [stream-controller]: seek to target start position 0.052244 from current time 0 buffer start 0.052244 stream-controller.ts:1143:13
09:57:26,834 [log] > [stream-controller]: Loading main sn: 4412 of level 0 (frag:[2.995-5.995]) cc: 0 [4411-4413], target: 2.995 base-stream-controller.ts:905:9
09:57:26,834 [log] > [stream-controller]: IDLE->FRAG_LOADING base-stream-controller.ts:2008:11
09:57:26,838 [log] > [stream-controller]: media seeking to 0.052, state: FRAG_LOADING base-stream-controller.ts:308:9
09:57:26,838 [log] > [audio-stream-controller]: media seeking to 0.052, state: STOPPED base-stream-controller.ts:308:9
09:57:26,838 [log] > [subtitle-stream-controller]: media seeking to 0.052, state: IDLE base-stream-controller.ts:308:9
09:57:26,842 [log] > [stream-controller]: Media seeked to 0.052 stream-controller.ts:576:11
09:57:26,911 [log] > [stream-controller]: Loaded main sn: 4412 of level 0 base-stream-controller.ts:526:15
09:57:26,926 [log] > [stream-controller]: FRAG_LOADING->PARSING base-stream-controller.ts:2008:11
09:57:26,947 [log] > [transmuxer.ts]: Flushed main sn: 4412 of level 0 transmuxer-interface.ts:395:40
09:57:26,995 [log] > [stream-controller]: PARSING->PARSED base-stream-controller.ts:2008:11
09:57:26,995 [log] > [stream-controller]: Parsed main sn: 4412 of level 0 (frag:[2.995-6.051]) base-stream-controller.ts:1955:9
09:57:26,995 [log] > [stream-controller]: Buffered main sn: 4412 of level 0 (frag:[2.995-6.051] > buffer:[0.052-5.991]) base-stream-controller.ts:713:9
09:57:26,995 [log] > [stream-controller]: PARSED->IDLE base-stream-controller.ts:2008:11
09:57:26,995 [log] > [stream-controller]: Loading main sn: 4413 of level 0 (frag:[5.991-8.991]) cc: 0 [4411-4413], target: 5.991 base-stream-controller.ts:905:9
09:57:26,995 [log] > [stream-controller]: IDLE->FRAG_LOADING base-stream-controller.ts:2008:11
09:57:27,116 [log] > [stream-controller]: Loaded main sn: 4413 of level 0 base-stream-controller.ts:526:15
09:57:27,152 [log] > [stream-controller]: FRAG_LOADING->PARSING base-stream-controller.ts:2008:11
09:57:27,173 [log] > [transmuxer.ts]: Flushed main sn: 4413 of level 0 transmuxer-interface.ts:395:40
09:57:27,210 [log] > [stream-controller]: PARSING->PARSED base-stream-controller.ts:2008:11
09:57:27,210 [log] > [stream-controller]: Parsed main sn: 4413 of level 0 (frag:[5.991-9.051]) base-stream-controller.ts:1955:9
09:57:27,210 [log] > [stream-controller]: Buffered main sn: 4413 of level 0 (frag:[5.991-9.051] > buffer:[0.052-8.986]) base-stream-controller.ts:713:9
09:57:27,210 [log] > [stream-controller]: PARSED->IDLE base-stream-controller.ts:2008:11
09:57:27,927 [log] > [level-controller]: Loading level index 0 with https://1600654994.rsc.cdn77.org/streaming-rtmp/ubicasttv/ovh_ubicasttv_d47167f23a35894c5e89c40f835431_720.m3u8 level-controller.ts:651:11
09:57:27,955 [log] > [level-controller]: live playlist 0 MISSED base-playlist-controller.ts:163:13
09:57:27,955 [log] > [level-controller]: reload live playlist 0 in 1470 ms base-playlist-controller.ts:290:11
09:57:27,956 [log] > [stream-controller]: Level 0 loaded [4411,4413][part-4413--1], cc [0, 0] duration:9.051244444444444 stream-controller.ts:669:9
09:57:27,956 [log] > [buffer-controller]: Updating MediaSource duration to 9.051 buffer-controller.ts:1308:13
09:57:29,427 [log] > [level-controller]: Loading level index 0 with https://1600654994.rsc.cdn77.org/streaming-rtmp/ubicasttv/ovh_ubicasttv_d47167f23a35894c5e89c40f835431_720.m3u8 level-controller.ts:651:11
09:57:29,455 [log] > [level-controller]: live playlist 0 MISSED base-playlist-controller.ts:163:13
09:57:29,456 [log] > [level-controller]: reload live playlist 0 in 1469 ms base-playlist-controller.ts:290:11
09:57:29,456 [log] > [stream-controller]: Level 0 loaded [4411,4413][part-4413--1], cc [0, 0] duration:9.051244444444444 stream-controller.ts:669:9
09:57:30,925 [log] > [level-controller]: Loading level index 0 with https://1600654994.rsc.cdn77.org/streaming-rtmp/ubicasttv/ovh_ubicasttv_d47167f23a35894c5e89c40f835431_720.m3u8 level-controller.ts:651:11
09:57:30,936 [log] > [level-controller]: live playlist 0 MISSED base-playlist-controller.ts:163:13
09:57:30,936 [log] > [level-controller]: reload live playlist 0 in 1489 ms base-playlist-controller.ts:290:11
09:57:30,936 [log] > [stream-controller]: Level 0 loaded [4411,4413][part-4413--1], cc [0, 0] duration:9.051244444444444 stream-controller.ts:669:9
09:57:32,425 [log] > [level-controller]: Loading level index 0 with https://1600654994.rsc.cdn77.org/streaming-rtmp/ubicasttv/ovh_ubicasttv_d47167f23a35894c5e89c40f835431_720.m3u8 level-controller.ts:651:11
09:57:32,600 [log] > [level-controller]: live playlist 0 REFRESHED 4415--1 base-playlist-controller.ts:163:13
09:57:32,600 [log] > [level-controller]: reload live playlist 0 in 2825 ms base-playlist-controller.ts:290:11
09:57:32,600 [log] > [stream-controller]: Level 0 loaded [4413,4415][part-4415--1], cc [0, 0] duration:9.060496145124734 stream-controller.ts:669:9
09:57:32,600 [log] > [buffer-controller]: Updating MediaSource duration to 15.051 buffer-controller.ts:1308:13
09:57:32,600 [log] > [stream-controller]: Loading main sn: 4414 of level 0 (frag:[9.051-12.051]) cc: 0 [4413-4415], target: 9.051 base-stream-controller.ts:905:9
09:57:32,600 [log] > [stream-controller]: IDLE->FRAG_LOADING base-stream-controller.ts:2008:11
09:57:32,694 [log] > [stream-controller]: Loaded main sn: 4414 of level 0 base-stream-controller.ts:526:15
09:57:32,707 [log] > [stream-controller]: FRAG_LOADING->PARSING base-stream-controller.ts:2008:11
09:57:32,724 [log] > [transmuxer.ts]: Flushed main sn: 4414 of level 0 transmuxer-interface.ts:395:40
...
```


### Chrome media internals output

_No response_
