Violentmonkey Beta fails to find enqueued images
https://community.metabrainz.org/t/ropdebees-userscripts-support-thread/551947/62

> It didn’t take long for the next bug to reveal itself using Violentmonkey BETA 2.13.0.19

```
instrument.js:102 [mb_enhanced_cover_art_uploads] Searching for images in Bandcamp release…
instrument.js:102 [mb_enhanced_cover_art_uploads] Found 1 image(s) in Bandcamp release
instrument.js:102 [mb_enhanced_cover_art_uploads] Fetching https://f4.bcbits.com/img/a0273152139_10.jpg (1/1)
instrument.js:102 [mb_enhanced_cover_art_uploads] Maximised https://f4.bcbits.com/img/a0273152139_10.jpg to https://f4.bcbits.com/img/a0273152139_0.jpg
instrument.js:102 [mb_enhanced_cover_art_uploads] Failed to enqueue some images Error: Could not find image a0273152139_0.0.png in queued uploads
    at assert (MB： Enhanced Cover Art Uploads.user.js:106014:4515)
    at assertDefined (MB： Enhanced Cover Art Uploads.user.js:106014:4592)
    at setImageParameters (MB： Enhanced Cover Art Uploads.user.js:108139:5)
    at _catch (MB： Enhanced Cover Art Uploads.user.js:106011:5950)
    at MB： Enhanced Cover Art Uploads.user.js:106014:9916
    at MB： Enhanced Cover Art Uploads.user.js:106011:3654
    at MB： Enhanced Cover Art Uploads.user.js:106014:9985
    at async Promise.all (/release/d21b249f-1770-4af3-9fad-8f5752a82b04/index 0)
(anonymous) @ instrument.js:102
onError @ MB： Enhanced Cover Art Uploads.user.js:106014
(anonymous) @ MB： Enhanced Cover Art Uploads.user.js:106014
fireHandlers @ MB： Enhanced Cover Art Uploads.user.js:106014
error @ MB： Enhanced Cover Art Uploads.user.js:106014
(anonymous) @ MB： Enhanced Cover Art Uploads.user.js:108528
Promise.then (async)
_catch @ MB： Enhanced Cover Art Uploads.user.js:106011
(anonymous) @ MB： Enhanced Cover Art Uploads.user.js:108525
t @ MB： Enhanced Cover Art Uploads.user.js:106011
_forOf @ MB： Enhanced Cover Art Uploads.user.js:106011
(anonymous) @ MB： Enhanced Cover Art Uploads.user.js:108520
Promise.then (async)
_continue @ MB： Enhanced Cover Art Uploads.user.js:106011
(anonymous) @ MB： Enhanced Cover Art Uploads.user.js:108508
_call @ MB： Enhanced Cover Art Uploads.user.js:106011
processSeedingParameters @ MB： Enhanced Cover Art Uploads.user.js:108504
(anonymous) @ MB： Enhanced Cover Art Uploads.user.js:108869
(anonymous) @ MB： Enhanced Cover Art Uploads.user.js:108879
(anonymous) @ MB： Enhanced Cover Art Uploads.user.js:108880
window.VMina7ijceh13uhapolm @ MB： Enhanced Cover Art Uploads.user.js:108880
i @ injected-web.js:1
Vt @ injected-web.js:1
set @ injected-web.js:1
(anonymous) @ MB： Enhanced Cover Art Uploads.user.js:1
pt @ VM309 injected.js:1
mt @ VM309 injected.js:1
await in mt (async)
ft @ VM309 injected.js:1
ut @ VM309 injected.js:1
await in ut (async)
(anonymous) @ VM309 injected.js:1
await in (anonymous) (async)
(anonymous) @ VM309 injected.js:1
Re @ VM309 injected.js:1
dt @ VM309 injected.js:1
qt @ VM309 injected.js:1
await in qt (async)
(anonymous) @ VM309 injected.js:1
n @ VM309 injected.js:1
(anonymous) @ VM309 injected.js:1
(anonymous) @ VM309 injected.js:1
instrument.js:102 [mb_enhanced_cover_art_uploads] Successfully added 1 image(s)
```
