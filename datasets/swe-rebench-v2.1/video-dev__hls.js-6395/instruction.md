CMCD "nor" and "d" should return part details during Low-Latency HLS streaming
### What version of Hls.js are you using?

dev (master branch): "d" introduced in v1.1, "nor" to be introduced in v1.6.0

### What browser (including version) are you using?

N/A

### What OS (including version) are you using?

N/A

### Test stream

Low-Latency HLS (any)

### Configuration

```JavaScript
default with `cmcd` enabled and `lowLatencyMode` enabled:


{
  "debug": true,
  "enableWorker": false,
  "lowLatencyMode": true,
  "cmcd": {}
}
```
```


### Additional player setup steps

N/A

### Checklist

- [X] The issue observed is not already reported by searching on Github under https://github.com/video-dev/hls.js/issues
- [X] The issue occurs in the stable client (latest release) on https://hlsjs.video-dev.org/demo and not just on my page
- [X] The issue occurs in the latest client (main branch) on https://hlsjs-dev.video-dev.org/demo and not just on my page
- [X] The stream has correct Access-Control-Allow-Origin headers (CORS)
- [X] There are no network errors such as 404s in the browser console when trying to play the stream

### Steps to reproduce

1. Play a Low-Latency HLS stream with CMCD enabled
https://hlsjs-dev.video-dev.org/demo/?src=https%3A%2F%2Fstream.mux.com%2Fv69RSHhFelSm4701snP22dYz2jICy4E4FUyk02rW4gxRM.m3u8&demoConfig=eyJlbmFibGVTdHJlYW1pbmciOnRydWUsImF1dG9SZWNvdmVyRXJyb3IiOnRydWUsInN0b3BPblN0YWxsIjpmYWxzZSwiZHVtcGZNUDQiOmZhbHNlLCJsZXZlbENhcHBpbmciOi0xLCJsaW1pdE1ldHJpY3MiOi0xfQ==

Note that fragment durations and next object (if any) is sent rather than part duration and part details for next part.

### Expected behaviour

The requests should always reflect the duration of the object being requested.

[HIDDEN]



### What actually happened?

1. CMCD= contains `d=2000` for the two second parent fragment of the one second partial segment being requested.
2. CMCD= is missing `nor` for the next part in the part list if there is one, or is listing a fragment if part loading is occurring far back enough

When only one part is listed for a fragment at the edge, duration may be reported correctly ("d=1000"). This is only a side effect of partial information being available at the edge of the playlist on certain playlist updates.

### Console output

```shell
Network panel request URL:

https://chunk-gcp-us-east4-vop1.cfcdn.mux.com/v1/chunk/nJjp4ZbZt00KBt9bMvpvuzqd2Q1IJNpdU8pgT59GmBofw7SgmSWxlEeBYaFqaJyua7S3R6b6KPJfsMBcf01ILudlhJAayiRdwqOi1vw01PaA400/11663.0.m4s?skid=default&signature=NjYzYTZjMjBfZWZhMGFmYjJlYjRhMTlmMTc3NDRjY2I1ZGIxMzFhMTdiZTE3YTg0Nzg3N2M0ZjQzZjQ3MDNhNWExODNjMTM3OQ==&zone=0&vsid=ZmHObqwz4tap4RFKSg6x3a5Ry25p6os9502KAOJWpnxF7krNPywQWX9Ic015w9Nloso1Zb9cBfIEBb4DurS39Zk5whswibZB5LJzClDGyauLb02diFSinbw1ZGkLikFAENc&CMCD=br%3D2564%2Cd%3D2000%2Cmtp%3D2600%2Cot%3Dv%2Csf%3Dh%2Csid%3D%22d79e2a45-4be0-43ce-884a-fc41c65ef4cd%22%2Csu%2Ctb%3D4712

`decodeURIComponent` output for CMCD field:
'br=2564,d=2000,mtp=2600,ot=v,sf=h,sid="d79e2a45-4be0-43ce-884a-fc41c65ef4cd",su,tb=4712'

NOR is missing because there is no next fragment (but there may be another part in the part list).
```


### Chrome media internals output

```shell
n/a
```

### Additional contract requirements

For a request that includes a low-latency part, the CMCD `d` value must represent the requested part's duration, not the duration of its containing segment. If a subsequent part is available, the CMCD `nor` value must identify that part, including when it belongs to the next segment.
