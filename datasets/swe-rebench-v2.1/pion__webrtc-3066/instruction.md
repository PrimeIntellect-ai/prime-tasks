Handling of undeclared SSRC for multimedia streams
Right now Pion only handles undeclared SSRC if the SDP contains a single media section.
We can extended this behavior to SDP with audio and single video description based on the payload type, without breaking simulcast or changing any behavior. [like chrome ](https://chromium.googlesource.com/external/webrtc/+/refs/heads/master/call/rtp_demuxer.cc#372)
I'm testing this and going to submit a PR.

related https://github.com/pion/webrtc/issues/880
