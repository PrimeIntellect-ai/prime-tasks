Seed Controller - Independent Proxy Configuration for each Seed
### Description of the feature you would like to add / User story

As a admin,
I would like to configure for different Seeds indiviual proxy servers (or no proxy at all)
in order to respect local envrionment restrication.

<!-- We've provided an example format of the user story below. You're free to use any other format as well. -->

### Solution details

In the current case we have
- on-premise master/seed with the need of an SSL rewriting proxy
- extra cloud seed without proxy
Currently the operator will set at every seed the same proxy https://github.com/kubermatic/kubermatic/blob/78be1a96ccbbd07552bedb15a6852a0d6c959e18/pkg/controller/operator/seed/resources/kubermatic/seed-controller-manager.go#L167

The field [`seed.proxySettings`](https://github.com/kubermatic/kubermatic/blob/2575151e82f29b300feb2330a312705ca47c945c/pkg/apis/kubermatic/v1/datacenter.go#L272) is currently used workers, but we need an option to overwrite the proxy settings of the seed controller manager objects.

<!-- Please, provide a bullet-pointed list or a few sentences of requirements that have to be met to mark the requested feature (user story) complete. -->

### Alternative approaches

<!-- Optional: A clear and concise description of any alternative solutions or features you've considered. -->



### Use cases

<!-- Optional: Please try to explain some use cases why this feature would be valuable for you. If you can, please also explain what metrics would be improved for you with having this feature. -->
see above


### Additional information

<!-- Optional: Additional information about the feature you're reporting. -->

#### *potential workaround*
scale the kubermatic-operator to 0 and patch the deployment manually

### Additional contract requirements

- A Seed that has its own proxy settings gets those settings in its seed-controller-manager deployment (the HTTP_PROXY, HTTPS_PROXY and NO_PROXY environment variables), instead of the proxy settings of the shared KubermaticConfiguration.
- A Seed without proxy settings gets no HTTP_PROXY or HTTPS_PROXY environment variable in its seed-controller-manager deployment, even if the shared KubermaticConfiguration defines a proxy.
- Different Seeds can have different proxy settings at the same time.
