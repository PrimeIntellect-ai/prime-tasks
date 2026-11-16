KubeConfigLoader does not support insecure-skip-tls-verify: true
KubeConfigLoader does not honor the `insecure-skip-tls-verify` cluster property mentioned on https://kubernetes.io/docs/user-guide/kubeconfig-file/

Obviously nobody should disable TLS verification, but it's sometimes useful for development etc :smirk:
