Prepend proxy sidecar to the container list to prevent application restarts
[Currently](https://github.com/Azure/azure-workload-identity/blob/37dc12fdf67ec0bd54d3e3f5c24273a0207707e8/pkg/webhook/webhook.go#L236C7-L236C7), proxy sidecar gets added to the end of the containers list. In this case, the application container may crash a couple of times before the sidecar becomes available.

I suggest prepending the sidecar to the containers list ([HIDDEN]), which will block all other containers due to the post-start hook in the sidecar.

### Additional contract requirements

- When injecting the proxy sidecar, place it before all existing containers and retain those containers in their original relative order.
