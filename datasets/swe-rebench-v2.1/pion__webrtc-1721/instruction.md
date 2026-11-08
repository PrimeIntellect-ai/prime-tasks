interceptor.UnbindLocalStream is never called
https://github.com/pion/webrtc/search?q=UnbindLocalStream

Resources which are released in `interceptor.UnbindLocalStream()` won't be freed.
It should be called on `PeerConnection.Close()`.
