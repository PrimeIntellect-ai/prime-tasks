Not compatible with endpoints that have a url_path (regression from boto)
Even though `url_path` is part of the `request_dict`, it is only ever set to `/`, the hard-coded default here https://github.com/boto/botocore/blob/20f8eb43d75a3d10cea3e4b5976be40be49c7660/botocore/serialize.py#L170.
This breaks endpoints such as `https://nova.rc.nectar.org.au:8773/services/Cloud`.

Here is an example how it worked with boto: https://support.rc.nectar.org.au/docs/boto

It would be great if this behaviour was preserved in botocore

### Additional contract requirements

When an endpoint URL has a non-root path, requests must retain that endpoint path when adding the request path. A root request path must not erase the endpoint path, and joining a request path must not introduce a duplicate separator when the endpoint path ends in `/`.
