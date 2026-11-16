HLS fails to stream video with name containing U+3000 character.
### What version of Hls.js are you using?

1.4.9

### What browser (including version) are you using?

Chrome

### What OS (including version) are you using?

Windows 10

### Test stream

_No response_

### Configuration

```JavaScript
{
  xhrSetup: function (xhr) {
   xhr.withCredentials = true;
 }
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

[ I paste the m3u8 content here as .m3u8 file is not allowed to be uploaded here]
[m3u8 1]
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-ALLOW-CACHE:YES
#EXT-X-TARGETDURATION:13
#EXTINF:12.133333,
sample-mp4-file_240p_00000.ts
#EXTINF:12.000000,
sample-mp4-file_240p_00001.ts
#EXTINF:6.000000,
sample-mp4-file_240p_00002.ts
#EXTINF:12.000000,
sample-mp4-file_240p_00003.ts
#EXTINF:12.000000,
sample-mp4-file_240p_00004.ts
#EXTINF:6.000000,
sample-mp4-file_240p_00005.ts
#EXTINF:12.000000,
sample-mp4-file_240p_00006.ts
#EXTINF:12.000000,
sample-mp4-file_240p_00007.ts
#EXTINF:6.000000,
sample-mp4-file_240p_00008.ts
#EXTINF:12.000000,
sample-mp4-file_240p_00009.ts
#EXTINF:12.000000,
sample-mp4-file_240p_00010.ts
#EXTINF:6.000000,
sample-mp4-file_240p_00011.ts
#EXTINF:5.933333,
sample-mp4-file_240p_00012.ts
#EXT-X-ENDLIST

[m3u8 2]
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-MEDIA-SEQUENCE:0
#EXT-X-ALLOW-CACHE:YES
#EXT-X-TARGETDURATION:13
#EXTINF:12.133333,
sample-mp4-file　_240p_00000.ts
#EXTINF:12.000000,
sample-mp4-file　_240p_00001.ts
#EXTINF:6.000000,
sample-mp4-file　_240p_00002.ts
#EXTINF:12.000000,
sample-mp4-file　_240p_00003.ts
#EXTINF:12.000000,
sample-mp4-file　_240p_00004.ts
#EXTINF:6.000000,
sample-mp4-file　_240p_00005.ts
#EXTINF:12.000000,
sample-mp4-file　_240p_00006.ts
#EXTINF:12.000000,
sample-mp4-file　_240p_00007.ts
#EXTINF:6.000000,
sample-mp4-file　_240p_00008.ts
#EXTINF:12.000000,
sample-mp4-file　_240p_00009.ts
#EXTINF:12.000000,
sample-mp4-file　_240p_00010.ts
#EXTINF:6.000000,
sample-mp4-file　_240p_00011.ts
#EXTINF:5.933333,
sample-mp4-file　_240p_00012.ts
#EXT-X-ENDLIST



1. Observe the difference between the ts files in each m3u8 file

- there is "　" character (u+3000) in the [m3u8 2] and no space in the [m3u8 1]

2. Upload the files to a file hosting e.g. https://tmpfiles.org/
4. Paste the url in https://hlsjs.video-dev.org/demo/ or  https://hlsjs-dev.video-dev.org/demo/
5. Open the network tab.
6. Observe and compare the ts file names it attempts to download and the ts file names listed in the m3u8 file itself
7. for [m3u8 1], the ts files to download are the same as those listed in the m3u8 file
8. for [m3u8 2], the ts files to download are different from those listed in the m3u8 files



### Expected behaviour

1. for [m3u8 1], the ts files to download are the same as those listed in the m3u8 file
2. for [m3u8 2], the ts files to download are also the same from those listed in the m3u8 files

### What actually happened?

Compare the ts file names in the m3u8 content and the files attempted to download. The u+3000 character caused it to get the wrong ts name.

Note: please ignore the 404 as I didnt upload the real ts files. The issue is the name of the ts files to download.

for [m3u8 1], the ts files to download are the same as those listed in the m3u8 file
![image](https://github.com/video-dev/hls.js/assets/55094043/bf128cd0-8bd8-4d28-858b-8e3a41511475)


for [m3u8 2], the ts files to download are different from those listed in the m3u8 files
![image](https://github.com/video-dev/hls.js/assets/55094043/4406bbb5-89db-4888-b358-6e377d389d44)


### Console output

```shell
NA
```


### Chrome media internals output

_No response_
