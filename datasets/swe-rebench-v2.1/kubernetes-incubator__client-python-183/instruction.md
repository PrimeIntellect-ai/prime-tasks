Contents of service account token mounted in POD is being base64 encoded
A project I have is using the client-python and using the mounted tokens wasn't working. After some investigation I figured out that the token file contents is being encoded in base64. From my understanding this content should not be encoded after read, the token should be ready to use.

[HIDDEN]

I have created a small project that illustrates the problem. I create a [ConfigMap](https://github.com/rafaelcaricio/kube-pods-lister/blob/0.1.0/deployment.yaml#L32-L57) which uses the service account token from the filesystem in a custom `kubeconfig`. Then I use the function [`new_client_from_config`](https://github.com/rafaelcaricio/kube-pods-lister/blob/0.1.0/pods_lister.py#L35) in my app passing this custom `kubeconfig`.

A work around I used for now is to split the `Bearer ` part of the header and decode the token and concat it back.
```python
authotization = config.api_key.get('authorization')
k, v = authorization.split(' ')
v = base64.decodebytes(v.encode())
request.headers['Authorization'] = "{} {}".format(k, v.decode())
```

Maybe I am missing the reason why the contents of the token file is being encoded in base64?
