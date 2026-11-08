pc.AddIceCandidate() should take RTCIceCandidateInit
See RTCIceCandidateInit: [w3c definition](https://w3c.github.io/webrtc-pc/#dom-rtcicecandidateinit)

## Issue
Current AddIceCandidate() takes a string, `candidate` component of RTCIceCandidateInit. In the future enhancement, we'd need sdpMLineIndex, sdpMid and usernameFragment fields to correctly pair the new candidates.

## Proposed approach
Handling of these field would require a huge modification to the current implementation of pion.  I'd assume we would like to incrementally enhance the feature. To do so, we should introduce RTCIceCandidateInit object for AddIceCandidate() method first.

To ensure backward compatibility, I'd suggest to chage the argument type from string to interface{}, then inside the function, we would use type switch to handle both string and (new) RTCCandidateInit object. (so that we could introduce this change in 1.x)

In 2.0, we can drop string arg, only accept RTCCandidateInit object.

### Additional contract requirements

- The Go method is `(*PeerConnection).AddICECandidate` and it accepts a single argument of the `ICECandidateInit` type.
- When a remote description has been set, `AddICECandidate` accepts a valid ICE candidate supplied through `ICECandidateInit.Candidate` and returns a nil error.
- `ICECandidateInit` exposes `SDPMLineIndex` (`*uint16`), `SDPMid` (`*string`), and `UsernameFragment` (`string`) fields for the corresponding ICE candidate metadata.
