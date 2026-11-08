ICEServer and RTCConfiguration cannot be marshaled to JSON
Consider the following:
```
func TestConfigurationJSONMarshal(t *testing.T) {
	j := `{
    "iceServers": [{"URLs": ["turn:turn.example.org"],
                    "username": "jch",
                    "credential": "topsecret",
                  }],
    "iceTransportPolicy": "relay",
    "bundlePolicy": "balanced",
    "rtcpMuxPolicy": "require"
}`

	conf := Configuration{
		ICEServers: []ICEServer{
			{
				URLs:       []string{"turn:turn.example.org"},
				Username:   "jch",
				Credential: "topsecret",
			},
		},
		ICETransportPolicy: ICETransportPolicyRelay,
		BundlePolicy:       BundlePolicyBalanced,
		RTCPMuxPolicy:      RTCPMuxPolicyRequire,
	}

	var conf2 Configuration
	err := json.Unmarshal([]byte(j), &conf2)
	assert.NoError(t, err)
	assert.Equal(t, conf, conf2)
}
```
This fails horribly:
```
--- FAIL: TestConfigurationJSONMarshal (0.00s)
    configuration_test.go:68:
        	Error Trace:	configuration_test.go:68
        	Error:      	Received unexpected error:
        	            	invalid character '}' looking for beginning of object key string
        	Test:       	TestConfigurationJSONMarshal
    configuration_test.go:69:
        	Error Trace:	configuration_test.go:69
        	Error:      	Not equal:
        	            	expected: webrtc.Configuration{ICEServers:[]webrtc.ICEServer{webrtc.ICEServer{URLs:[]string{"turn:turn.example.org"}, Username:"jch", Credential:"topsecret", CredentialType:0}}, ICETransportPolicy:1, BundlePolicy:1, RTCPMuxPolicy:2, PeerIdentity:"", Certificates:[]webrtc.Certificate(nil), ICECandidatePoolSize:0x0, SDPSemantics:0}
        	            	actual  : webrtc.Configuration{ICEServers:[]webrtc.ICEServer(nil), ICETransportPolicy:0, BundlePolicy:0, RTCPMuxPolicy:0, PeerIdentity:"", Certificates:[]webrtc.Certificate(nil), ICECandidatePoolSize:0x0, SDPSemantics:0}

        	            	Diff:
        	            	--- Expected
        	            	+++ Actual
        	            	@@ -1,15 +1,6 @@
        	            	 (webrtc.Configuration) {
        	            	- ICEServers: ([]webrtc.ICEServer) (len=1) {
        	            	-  (webrtc.ICEServer) {
        	            	-   URLs: ([]string) (len=1) {
        	            	-    (string) (len=21) "turn:turn.example.org"
        	            	-   },
        	            	-   Username: (string) (len=3) "jch",
        	            	-   Credential: (string) (len=9) "topsecret",
        	            	-   CredentialType: (webrtc.ICECredentialType) 0
        	            	-  }
        	            	- },
        	            	- ICETransportPolicy: (webrtc.ICETransportPolicy) 1,
        	            	- BundlePolicy: (webrtc.BundlePolicy) 1,
        	            	- RTCPMuxPolicy: (webrtc.RTCPMuxPolicy) 2,
        	            	+ ICEServers: ([]webrtc.ICEServer) <nil>,
        	            	+ ICETransportPolicy: (webrtc.ICETransportPolicy) 0,
        	            	+ BundlePolicy: (webrtc.BundlePolicy) 0,
        	            	+ RTCPMuxPolicy: (webrtc.RTCPMuxPolicy) 0,
        	            	  PeerIdentity: (string) "",
        	Test:       	TestConfigurationJSONMarshal
FAIL
```
There are two issues here:
  * the types `Configuration` and `ICEServer` do not have the required `json` tags;
  * a number of fields are numeric instead of being strings.

How do people want this fixed?  I can either make the relevant fields into strings, or write custom marshallers/unmarshallers.  The alternative would be to work around this issue in client code, but I find that distasteful.
