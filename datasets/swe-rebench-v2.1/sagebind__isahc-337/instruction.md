Get metrics even a request fails
Hi, thanks for this great lib!

I'm using it to implement a network debugging tool for our client, utilizing it's great metrics interface. In this context, error is expected and I want to extract metrics from the request. Is this currently possible? The phase throwing the error can be observed from the error's Kind, so specifically I need remote_addr of this failed request.
