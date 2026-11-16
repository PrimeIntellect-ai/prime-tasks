Codec ignored due to case sensitive MimeType check
<!--
  Come join our community on Slack https://pion.ly/slack for quicker support and more resources

  We also provide a Knowledge Base https://pion.ly/knowledge-base that covers Pion and general WebRTC

  We maintain a FAQ of common issues and questions https://pion.ly/knowledge-base/pion-basics/faq/

 Please answer these questions before submitting your issue. Thanks!
-->

### Your environment.
  - Version: 3.1.24 (can be repro'd on latest webrtc `master`)

### What did you do?
Initialised a `MediaEngine` with two codecs registered `VP8` (MimeType = `video/vp8`) and `H264` (MimeType = `video/h264`).
Called `PeerConnection.SetRemoteDescription` with an `offer` sdp which has two codecs - VP8 and H264.
Creating the answer sdp using `PeerConnection.CreateAnswer` we get sdp which has only `H264` codec.

### What did you expect?
Expected both VP8 and H264 codec to be present in the Answer SDP

### What happened?
[HIDDEN]
