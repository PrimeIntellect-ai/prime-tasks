conflict extmap id of header extensions
<!--
  Come join our community on Slack https://pion.ly/slack for quicker support and more resources

  We also provide a Knowledge Base https://pion.ly/knowledge-base that covers Pion and general WebRTC

  We maintain a FAQ of common issues and questions https://pion.ly/knowledge-base/pion-basics/faq/

 Please answer these questions before submitting your issue. Thanks!
-->

### Your environment.
  - Version: *Release or SHA*
  - Browser: *include version*
  - Other Information - *stacktraces, related issues, suggestions how to fix, links for us to have context*

### What did you do?
<!--
If possible, provide an example for reproducing the error.
A complete runnable program is good.
-->

#2220 will generate duplicate extmap id for different uri, it can't pass this test case:

```
	t.Run("unique extmapid with different codec", func(t *testing.T) {
		m := &MediaEngine{}
		registerCodec(m)
		assert.NoError(t, m.RegisterHeaderExtension(RTPHeaderExtensionCapability{"pion-header-test"}, RTPCodecTypeAudio))
		assert.NoError(t, m.RegisterHeaderExtension(RTPHeaderExtensionCapability{"pion-header-test2"}, RTPCodecTypeVideo))

		audio := m.getRTPParametersByKind(RTPCodecTypeAudio, []RTPTransceiverDirection{RTPTransceiverDirectionRecvonly})
		video := m.getRTPParametersByKind(RTPCodecTypeVideo, []RTPTransceiverDirection{RTPTransceiverDirectionRecvonly})

		assert.Equal(t, 1, len(audio.HeaderExtensions))
		assert.Equal(t, 1, len(video.HeaderExtensions))
		assert.NotEqual(t, audio.HeaderExtensions[0].ID, video.HeaderExtensions[0].ID)
	})
```


### What did you expect?

generate unique extmap id for different extension uri in all media sections

### What happened?
