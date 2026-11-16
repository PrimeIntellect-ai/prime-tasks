v1.4.0-beta regression gap controller jumps large gaps
I noticed one undesirable action: `gap-controller.ts:264 [warn] > skipping hole, adjusting currentTime from 105.275674 to 170.05533300000002`

To reproduce the issue, you need to watch the entire video and seek to 105.
` "backBufferLength": 90 `
[08b938f3.hls-js-dev.pages.dev-1680185898252.log](https://github.com/video-dev/hls.js/files/11112822/08b938f3.hls-js-dev.pages.dev-1680185898252.log)

_Originally posted by @mtoczko in https://github.com/video-dev/hls.js/issues/2940#issuecomment-1490433044_

### Additional contract requirements

- The gap controller must not skip a large gap (a gap larger than `maxBufferHole`) unless it is a start gap or every fragment spanning the gap is a partial fragment. If no fragments are known to span a large gap, it is not eligible for skipping. When every fragment spanning the gap is partial, the large gap is skipped and the playback position advances past the gap.
