ipv6 string with mask between 33 and 128 are rejected.
#### Context

* *node version*: 4.2.6
* *joi version*: 10.6.0
* *environment* (node, browser): node
* *used with* (hapi, standalone, ...): hapi
* *any other relevant information*:

#### What are you trying to achieve or the steps to reproduce ?

When using Joi to validate ipv4 string and ipv6 string, there is a problem with cidr subnet mask : it cannot go over /32, witch is good for ipv4, but for ipv6 it can go up to /128.
Here is a little code to illustrate:

```js
'use strict'

const Joi = require('joi')
const Hapi = require('hapi')

const server = new Hapi.Server();

server.connection({
    host: 'localhost',
    port: 8000
});


server.route({
    method: 'GET',
    path:'/testIP/{ip*}',
    handler: function (request, reply) {
        return reply(`For Joi, ${request.params.ip} is a valid ip.`);
    },
	config: {
		validate: {
			params: {
				ip: Joi.string()
				.ip({
					version: ['ipv4', 'ipV6'],
					cidr: 'optional'
				})
				.required()
			}
		}
	}
});

server.start((err) => {
    if (err) {
        throw err;
    }
    console.log('Server running at:', server.info.uri);
})
```

#### Which result you had ?
http://localhost:8000/testIP/foo
-> 400, ok

http://localhost:8000/testIP/192.128.0.0.0
-> 400, ok

http://localhost:8000/testIP/192.128.0.0
-> 200, ok

http://localhost:8000/testIP/192.128.0.0/16
-> 200, ok

http://localhost:8000/testIP/192.128.0.0/32
-> 200, ok

http://localhost:8000/testIP/192.128.0.0/33
-> 400, ok

http://localhost:8000/testIP/ff:
-> 400, ok

http://localhost:8000/testIP/ff::
-> 200, ok

http://localhost:8000/testIP/ff::/22
-> 200, ok

http://localhost:8000/testIP/ff::/32
-> 200, ok

http://localhost:8000/testIP/ff::/33
-> 400, KO: should work !

http://localhost:8000/testIP/ff::/128
-> 400, KO: should work !

http://localhost:8000/testIP/ff::/64
-> 400, KO; should work !

http://localhost:8000/testIP/ff::/129
-> 400, ok

#### What did you expect ?

ipv6 must be allowed to have a mask up to /128.
