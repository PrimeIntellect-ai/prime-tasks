controller: mark all volume mounts readOnly=true
*Description*:

The AI Gateway ExtProc deployment/containers mount some secrets/configmaps. However, it only needs to read the contents, and so the write permission is unnecessary.

[optional *Relevant Links*:]

I would like the `corev1.VolumeMount`'s ReadOnly flag to always true in https://github.com/envoyproxy/ai-gateway/blob/main/internal/controller/sink.go
