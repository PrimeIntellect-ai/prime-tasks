Delta updates with EXT-X-DISCONTINUITY don't work correctly
### What version of Hls.js are you using?

v1.5.18

### What browser (including version) are you using?

Chrome 131.0.6778.205（Official Build） （arm64）

### What OS (including version) are you using?

macOS Sonoma 14.7.2

### Test stream

_No response_

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

1. Play event playlist contains a segment with `#EXT-X-DISCONTINUITY` by using delta update:

```
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-VERSION:9
#EXT-X-SERVER-CONTROL:CAN-SKIP-UNTIL=36
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:6.00000,
fileSequence0.ts
#EXTINF:6.00000,
fileSequence1.ts
#EXT-X-DISCONTINUITY
#EXTINF:6.00000,
fileSequence2.ts
#EXTINF:6.00000,
fileSequence3.ts
#EXTINF:6.00000,
fileSequence4.ts
#EXTINF:6.00000,
fileSequence5.ts
#EXTINF:6.00000,
fileSequence6.ts
```

2. Wait until the segment with `#EXT-X-DISCONTINUITY` is skipped from delta playlist:

```
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-VERSION:9
#EXT-X-SERVER-CONTROL:CAN-SKIP-UNTIL=36
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-SKIP:SKIPPED-SEGMENTS=3
#EXTINF:6.00000,
fileSequence3.ts
#EXTINF:6.00000,
fileSequence4.ts
#EXTINF:6.00000,
fileSequence5.ts
#EXTINF:6.00000,
fileSequence6.ts
#EXTINF:6.00000,
fileSequence7.ts
#EXTINF:6.00000,
fileSequence8.ts
#EXTINF:6.00000,
fileSequence9.ts
```

[note] Complete playlist at this time:

```
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-VERSION:9
#EXT-X-SERVER-CONTROL:CAN-SKIP-UNTIL=36
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:6.00000,
fileSequence0.ts
#EXTINF:6.00000,
fileSequence1.ts
#EXT-X-DISCONTINUITY
#EXTINF:6.00000,
fileSequence2.ts
#EXTINF:6.00000,
fileSequence3.ts
#EXTINF:6.00000,
fileSequence4.ts
#EXTINF:6.00000,
fileSequence5.ts
#EXTINF:6.00000,
fileSequence6.ts
#EXTINF:6.00000,
fileSequence7.ts
#EXTINF:6.00000,
fileSequence8.ts
#EXTINF:6.00000,
fileSequence9.ts
```

### Expected behaviour

No problems.

### What actually happened?

`[warn] > discontinuity sliding from playlist, take drift into account` logging occurs on each playlist update. On each time, discontinuity sequence numbers (cc) of each segment are shift.

![image](https://github.com/user-attachments/assets/e9c15271-3f56-45d6-be4c-648b40ca82cc)


### Console output

```shell
level-controller.ts:600 [log] > [level-controller]: Loading level index 1 with http://localhost:8000/high/lowLatencyHLS.m3u8?_HLS_skip=YES
base-playlist-controller.ts:148 [log] > [level-controller]: live playlist 1 REFRESHED 8--1
base-playlist-controller.ts:263 [log] > [level-controller]: reload live playlist 1 in 5988 ms
stream-controller.ts:642 [log] > [stream-controller]: Level 1 loaded [0,8][part-8--1], cc [0, 1] duration:54
base-stream-controller.ts:767 [log] > [stream-controller]: Loading fragment 8 cc: 1 of [0-8] level: 1, target: 48
base-stream-controller.ts:1810 [log] > [stream-controller]: IDLE->FRAG_LOADING
buffer-controller.ts:862 [log] > [buffer-controller] Updating Media Source duration to 54.000
base-stream-controller.ts:398 [log] > [stream-controller]: Loaded fragment 8 of level 1
transmuxer-interface.ts:394 [log] > last AAC PES packet truncated,might overlap between fragments
base-stream-controller.ts:1810 [log] > [stream-controller]: FRAG_LOADING->PARSING
transmuxer-interface.ts:394 [log] > last AAC PES packet truncated,might overlap between fragments
transmuxer-interface.ts:394 [log] > [transmuxer.ts]: Flushed fragment 8 of level 1
base-stream-controller.ts:1810 [log] > [stream-controller]: PARSING->PARSED
base-stream-controller.ts:579 [log] > [stream-controller]: Buffered main sn: 8 of level 1 (frag:[48.000-54.000] > buffer:[12.011-53.995])
base-stream-controller.ts:1810 [log] > [stream-controller]: PARSED->IDLE
level-controller.ts:600 [log] > [level-controller]: Loading level index 1 with http://localhost:8000/high/lowLatencyHLS.m3u8?_HLS_skip=YES
base-playlist-controller.ts:148 [log] > [level-controller]: live playlist 1 REFRESHED 9--1
level-helper.ts:236 [warn] > discontinuity sliding from playlist, take drift into account
mergeDetails @ level-helper.ts:236
playlistLoaded @ base-playlist-controller.ts:160
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
set @ level-controller.ts:481
set @ level-controller.ts:633
set @ hls.ts:581
startLoad @ stream-controller.ts:143
startLoad @ hls.ts:435
filterAndSortMediaOptions @ level-controller.ts:376
onManifestLoaded @ level-controller.ts:200
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handleMasterPlaylist @ playlist-loader.ts:429
onSuccess @ playlist-loader.ts:327
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onManifestLoading @ playlist-loader.ts:154
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadSource @ hls.ts:420
loadSelectedStream @ main.js:383
(anonymous) @ main.js:225
j @ jquery.min.js:2
fireWith @ jquery.min.js:2
ready @ jquery.min.js:2
I @ jquery.min.js:2Understand this warningAI
base-playlist-controller.ts:263 [log] > [level-controller]: reload live playlist 1 in 5986 ms
stream-controller.ts:642 [log] > [stream-controller]: Level 1 loaded [0,9][part-9--1], cc [1, 0] duration:60
base-stream-controller.ts:767 [log] > [stream-controller]: Loading fragment 9 cc: 1 of [0-9] level: 1, target: 54
base-stream-controller.ts:1810 [log] > [stream-controller]: IDLE->FRAG_LOADING
buffer-controller.ts:862 [log] > [buffer-controller] Updating Media Source duration to 60.000
base-stream-controller.ts:398 [log] > [stream-controller]: Loaded fragment 9 of level 1
base-stream-controller.ts:1810 [log] > [stream-controller]: FRAG_LOADING->PARSING
transmuxer-interface.ts:394 [log] > [transmuxer.ts]: Flushed fragment 9 of level 1
base-stream-controller.ts:1810 [log] > [stream-controller]: PARSING->PARSED
base-stream-controller.ts:579 [log] > [stream-controller]: Buffered main sn: 9 of level 1 (frag:[53.995-60.011] > buffer:[12.011-60.000])
base-stream-controller.ts:1810 [log] > [stream-controller]: PARSED->IDLE
level-controller.ts:600 [log] > [level-controller]: Loading level index 1 with http://localhost:8000/high/lowLatencyHLS.m3u8?_HLS_skip=YES
base-playlist-controller.ts:148 [log] > [level-controller]: live playlist 1 REFRESHED 10--1
level-helper.ts:236 [warn] > discontinuity sliding from playlist, take drift into account
mergeDetails @ level-helper.ts:236
playlistLoaded @ base-playlist-controller.ts:160
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
(anonymous) @ base-playlist-controller.ts:285
setTimeout
playlistLoaded @ base-playlist-controller.ts:284
onLevelLoaded @ level-controller.ts:575
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handlePlaylistLoaded @ playlist-loader.ts:683
handleTrackOrLevelPlaylist @ playlist-loader.ts:505
onSuccess @ playlist-loader.ts:319
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onLevelLoading @ playlist-loader.ts:166
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadPlaylist @ level-controller.ts:614
set @ level-controller.ts:481
set @ level-controller.ts:633
set @ hls.ts:581
startLoad @ stream-controller.ts:143
startLoad @ hls.ts:435
filterAndSortMediaOptions @ level-controller.ts:376
onManifestLoaded @ level-controller.ts:200
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
handleMasterPlaylist @ playlist-loader.ts:429
onSuccess @ playlist-loader.ts:327
readystatechange @ xhr-loader.ts:238
XMLHttpRequest.send
openAndSendXhr @ xhr-loader.ts:165
loadInternal @ xhr-loader.ts:124
load @ xhr-loader.ts:82
load @ playlist-loader.ts:352
onManifestLoading @ playlist-loader.ts:154
emit @ index.js:203
emit @ hls.ts:310
trigger @ hls.ts:318
loadSource @ hls.ts:420
loadSelectedStream @ main.js:383
(anonymous) @ main.js:225
j @ jquery.min.js:2
fireWith @ jquery.min.js:2
ready @ jquery.min.js:2
I @ jquery.min.js:2Understand this warningAI
base-playlist-controller.ts:263 [log] > [level-controller]: reload live playlist 1 in 5986 ms
stream-controller.ts:642 [log] > [stream-controller]: Level 1 loaded [0,10][part-10--1], cc [2, 0] duration:66.01066666666667
base-stream-controller.ts:767 [log] > [stream-controller]: Loading fragment 10 cc: 1 of [0-10] level: 1, target: 60.011
base-stream-controller.ts:1810 [log] > [stream-controller]: IDLE->FRAG_LOADING
buffer-controller.ts:862 [log] > [buffer-controller] Updating Media Source duration to 66.011
base-stream-controller.ts:398 [log] > [stream-controller]: Loaded fragment 10 of level 1
base-stream-controller.ts:1810 [log] > [stream-controller]: FRAG_LOADING->PARSING
transmuxer-interface.ts:394 [log] > [transmuxer.ts]: Flushed fragment 10 of level 1
base-stream-controller.ts:1810 [log] > [stream-controller]: PARSING->PARSED
base-stream-controller.ts:579 [log] > [stream-controller]: Buffered main sn: 10 of level 1 (frag:[60.000-66.005] > buffer:[12.011-66.000])
base-stream-controller.ts:1810 [log] > [stream-controller]: PARSED->IDLE
```


### Chrome media internals output

_No response_
