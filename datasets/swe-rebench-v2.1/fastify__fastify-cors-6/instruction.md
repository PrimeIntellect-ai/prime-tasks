Pass fastify instance to origin function
Hi. In order to allow usage of previously registered modules and plugins (e.g. like fastify-mongo or others) in origin function it will be good if fastify instance will be passed there as parameter.

Now it's only an option to use closure for that, but that limits a bit where that function could be declared.
