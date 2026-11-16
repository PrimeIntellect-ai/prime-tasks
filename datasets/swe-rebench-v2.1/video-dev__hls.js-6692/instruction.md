jump back while play live stream
### What do you want to do with Hls.js?

My live stream has an m3u8 file that comes with 3 TS segments and a 2-second pre-segment.
When the pull-side experiences poor network conditions, the player jumps back to the start of the live stream with the following log:

```Playback: 30.915 is located too far from the end of the live sliding playlist: 6, reset currentTime to: 0.000```

I want to pause the player and wait until the network conditions improve.
I'm not sure if this is a bug or just a configuration mistake. Hlsjs version is 1.5.5
I checked the exist issue #5282 .

### What have you tried so far?

1. I checked the incoming m3u8 file, and it looks like the following:

```
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-ALLOW-CACHE:NO
#EXT-X-MEDIA-SEQUENCE:14
#EXT-X-TARGETDURATION:2
#EXTINF:2,
test-tenant_test-channel_16ML7qBzR_test1-14.ts?txspiseq=108791770971209728929
#EXTINF:2,
test-tenant_test-channel_16ML7qBzR_test1-15.ts?txspiseq=108791770971209728929
#EXTINF:2,
test-tenant_test-channel_16ML7qBzR_test1-16.ts?txspiseq=108791770971209728929
```
2. I tested my stream using the Hls.js demo project and was able to reproduce the "jump back" issue.
3. I debugged the synchronizeToLiveEdge method in base-stream-controller.
The hls.liveSyncPosition is 0.000, which causes the player to jump to the start of the live stream.
4. After checking the LevelDetail object,
I noticed that PTSKnown is false, and fragments[0].start is 0.
Shouldn't synchronizeToLiveEdge be called after Hls.Events.LEVEL_PTS_UPDATED?

### Additional contract requirements

When a live playlist refresh advances beyond every fragment in the previous playlist, the refreshed fragments must continue from the previous timeline edge rather than restarting at zero. This prevents playback from jumping back to the start of the live stream.
