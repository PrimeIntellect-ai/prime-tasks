Invalid request call when hapi host is set to 0.0.0.0
#### Context

* *hapi-swgger version*: 9.0.2
* *any other relevant information*: Hapi 17.2.0

#### What are you trying to achieve or the steps to reproduce ?

I want to run hapi server on all my network interfaces (NIC) so I'm using following host: ```0.0.0.0```. While Swagger UI is displayed correctly, request executed through it does not work because it is invoked against host taken from Hapi configuration - ```0.0.0.0```.

```js
const server = new Hapi.Server({
    host: '0.0.0.0',
    port: 8083
});
```

#### What result did you get?
When I execute swagger request when I'm connected from whatever domain eg.
```http://192.168.0.55:8083/api/docs``` (NIC 1) or
```http://internal.domain.com:8083/api/docs``` (the same NIC 1) or
```http://my.public.domain.com:8083/api/docs``` (NIC 2)
```http:/123.123.123.123:8083/api/docs``` (the same NIC 2)

all requests are executed as ```http://0.0.0.0:8083/api/config```

#### What did you expect ?
host for building request url should be taken directly from the browser - not Hapi configuration

It worked properly in hapi-swagger v8 and now it is broken

### Additional contract requirements

- The generated Swagger JSON `host` must be `194.418.15.24:7645` when the request Host value is `194.418.15.24:7645`, and `194.418.15.24` when the request Host value is `194.418.15.24:80`.
