small fragment incorrectly skipped
### What version of Hls.js are you using?

latest

### What browser (including version) are you using?

irrelevent

### What OS (including version) are you using?

irrelevent

### Test stream

_No response_

### Configuration

```JavaScript
default
```


### Additional player setup steps

_No response_

### Checklist

- [X] The issue observed is not already reported by searching on Github under https://github.com/video-dev/hls.js/issues
- [X] The issue occurs in the stable client (latest release) on https://hls-js.netlify.com/demo and not just on my page
- [X] The issue occurs in the latest client (main branch) on https://hls-js-dev.netlify.com/demo and not just on my page
- [X] The stream has correct Access-Control-Allow-Origin headers (CORS)
- [X] There are no network errors such as 404s in the browser console when trying to play the stream

### Steps to reproduce

grab any stream with fragment duration less than default maxFragLookUpTolerance

in our case, the small fragment is at the end of range between two discontinue tag

the last fragment is always skipped by fragment finder.

### Expected behaviour

fragment not being skipped

### What actually happened?

fragment is skipped

### Console output

```shell
irrelevent
```


### Chrome media internals output

_No response_
