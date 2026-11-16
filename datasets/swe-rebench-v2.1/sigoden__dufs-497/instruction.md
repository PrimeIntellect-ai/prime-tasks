401 when external basic auth enabled with forwarded headers
First: not sure I would consider that a bug from dufs side at best an unexpected behavior, I will let you judge about it.
Feel free to close.

**Problem**

I was putting dufs behind traefik and traefik was handling the auth part with basic auth and dufs was behind.
dufs was launched with

`dufs /data -A`

So everyone is welcome, no user or anything.
Every time I logged successfully with traefik I was getting a 401 from dufs just after that.

Turn out that because traefik was passing the headers from basic auth to dufs, it would not recognize user and was 401, with no log from dufs except the 401.

I was expecting dufs to not check anything as I set nothing on startup command.
Maybe it's a wrong expectation but I would expect to ignore auth header when no auth is configured.

Solved the issue by configuring traefik to not forward headers.

That was my return, mostly on my side.
Have a good day and thanks for this beautiful piece of code :)
