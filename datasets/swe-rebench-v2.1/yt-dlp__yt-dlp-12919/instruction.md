Hyphen not allowed in CDA's channel name
### Checklist

- [x] I'm reporting that yt-dlp is broken on a **supported** site
- [x] I've verified that I have **updated yt-dlp to nightly or master** ([update instructions](https://github.com/yt-dlp/yt-dlp#update-channels))
- [x] I've checked that all provided URLs are playable in a browser with the same IP and same login details
- [x] I've checked that all URLs and arguments with special characters are [properly quoted or escaped](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#video-url-contains-an-ampersand--and-im-getting-some-strange-output-1-2839-or-v-is-not-recognized-as-an-internal-or-external-command)
- [x] I've searched [known issues](https://github.com/yt-dlp/yt-dlp/issues/3766), [the FAQ](https://github.com/yt-dlp/yt-dlp/wiki/FAQ), and the [bugtracker](https://github.com/yt-dlp/yt-dlp/issues?q=is%3Aissue%20-label%3Aspam%20%20) for similar issues **including closed ones**. DO NOT post duplicates
- [x] I've read about [sharing account credentials](https://github.com/yt-dlp/yt-dlp/blob/master/CONTRIBUTING.md#are-you-willing-to-share-account-details-if-needed) and I'm willing to share it if required

### Region

Poland

### Provide a description that is worded well enough to be understood

CDA's folder downloader does not allow hyphens in channel names, while there are ones on the CDA service.
Example: https://www.cda.pl/FILMY-SERIALE-ANIME-KRESKOWKI-BAJKI

### Provide verbose output that clearly demonstrates the problem

- [x] Run **your** yt-dlp command with **-vU** flag added (`yt-dlp -vU <your command line>`)
- [ ] If using API, add `'verbose': True` to `YoutubeDL` params instead
- [x] Copy the WHOLE output (starting with `[debug] Command-line config`) and insert it below

### Complete Verbose Output

```shell
$ yt-dlp -vU https://www.cda.pl/FILMY-SERIALE-ANIME-KRESKOWKI-BAJKI/folder/18493422
[debug] Command-line config: ['-vU', 'https://www.cda.pl/FILMY-SERIALE-ANIME-KRESKOWKI-BAJKI/folder/18493422']
[debug] Encodings: locale UTF-8, fs utf-8, pref UTF-8, out utf-8, error utf-8, screen utf-8
[debug] yt-dlp version stable@2025.03.31 from yt-dlp/yt-dlp [5e457af57]
[debug] Python 3.13.2 (CPython x86_64 64bit) - Linux-6.12.21-1-lts-x86_64-with-glibc2.41 (OpenSSL 3.4.1 11 Feb 2025, glibc 2.41)
[debug] exe versions: ffmpeg 7.1 (setts), ffprobe 7.1, rtmpdump 2.4
[debug] Optional libraries: Cryptodome-3.22.0, brotlicffi-1.1.0.0, certifi-2025.01.31, mutagen-1.47.0, requests-2.32.3, secretstorage-3.3.3, sqlite3-3.49.1, urllib3-2.3.0, websockets-12.0 (unsupported)
[debug] Proxy map: {}
[debug] Request Handlers: urllib, requests
[debug] Plugin directories: none
[debug] Loaded 1850 extractors
[debug] Fetching release info: https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest
Latest version: stable@2025.03.31 from yt-dlp/yt-dlp
yt-dlp is up to date (stable@2025.03.31 from yt-dlp/yt-dlp)
[generic] Extracting URL: https://www.cda.pl/FILMY-SERIALE-ANIME-KRESKOWKI-BAJKI/folder/18493422
[generic] 18493422: Downloading webpage
WARNING: [generic] Falling back on generic information extractor
[generic] 18493422: Extracting information
[debug] Looking for embeds
ERROR: Unsupported URL: https://www.cda.pl/FILMY-SERIALE-ANIME-KRESKOWKI-BAJKI/folder/18493422
Traceback (most recent call last):
  File "/usr/lib/python3.13/site-packages/yt_dlp/YoutubeDL.py", line 1653, in wrapper
    return func(self, *args, **kwargs)
  File "/usr/lib/python3.13/site-packages/yt_dlp/YoutubeDL.py", line 1788, in __extract_info
    ie_result = ie.extract(url)
  File "/usr/lib/python3.13/site-packages/yt_dlp/extractor/common.py", line 748, in extract
    ie_result = self._real_extract(url)
  File "/usr/lib/python3.13/site-packages/yt_dlp/extractor/generic.py", line 2578, in _real_extract
    raise UnsupportedError(url)
yt_dlp.utils.UnsupportedError: Unsupported URL: https://www.cda.pl/FILMY-SERIALE-ANIME-KRESKOWKI-BAJKI/folder/18493422
```
