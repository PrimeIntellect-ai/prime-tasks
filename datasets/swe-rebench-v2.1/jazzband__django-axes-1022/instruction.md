Possibility to override get_client_ip method
Hi,

First of all, thank you for this package and your work !

My problem is that I cannot find a proper configuration for _django_ipware_ that fits my case.

My server is behind a load balancer and a reverse proxy.
The load balancer is configured in append mode and so appends the client ip address to the `X-Forwarded-For` header existing values or create the header with the client ip address if it does not exist in the request.
The reverse proxy does nothing in particular with this header, just passes it to the server.

So, I get something like this on the server: `X-Forwarded-For = <original_data_from_client> -- ...   -- <client_ip_set_by_load_balancer>`.

I configure _django-axes_ with `AXES_PROXY_ORDER = 'right-most'` as I want _django-axes_ to get the last ip address contained in the header, even if other values are invalid.

_django_ipware_ does not enable that. It skips the whole header if the first or the last ip address is not a valid one.
https://github.com/un33k/django-ipware/blob/master/ipware/ip.py#L27
https://github.com/un33k/django-ipware/blob/930f3293eb11b2bfc221959434e8501c165a2b61/ipware/utils.py#L94

If I try to spoof my ip address using a valid ip address, all works good, _django_axes_ gets the `most-right` ones but if I set an invalid ip address in the header, the whole header is skipped.

I don't know what would be the best way to fix that, if I should open an issue in _django_ipware_  or update _django-axes_ to add the possibility to define a custom  and simple `get_client_ip` method in this case ?

Thank you !

### Additional contract requirements

- Axes provides the Django setting `AXES_CLIENT_IP_CALLABLE` to configure project-specific client-IP resolution. When configured with a callable or dotted import path, Axes supplies the incoming request and uses the resolver's returned address.
- When no custom resolver is configured, Axes retains its existing django-ipware client-IP lookup.
