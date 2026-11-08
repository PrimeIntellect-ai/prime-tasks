Sometimes the updater sends the message "OK" when failing
Following up on #615, I just had the following error in the docker logs:
```
🔔 Successfully pinged Uptime Kuma
⏰ Checking the IP addresses in about 5m0s . . .
😞 Failed to send HTTP(S) request to "https://1.1.1.1/cdn-cgi/trace": context deadline exceeded
😞 Failed to detect the IPv4 address
🔔 Successfully pinged Uptime Kuma
⏰ Checking the IP addresses in about 4m55s . . .
🌐 Detected the IPv4 address: 71.x.y.86
🤷 The A records of "ddns.domain.com" are already up to date
🔔 Successfully pinged Uptime Kuma
⏰ Checking the IP addresses in about 5m0s . . .
```
Which is totally fine (I rebooted my router, so the container was running, but it couldn't reach the internet for that one interval).
However this is what Uptime Kuma showed:
![image](https://github.com/favonia/cloudflare-ddns/assets/90044149/828f814c-b1b3-4577-84b5-fe4db2e7504a)
(So it sent an OK instead of the actual issue of "context deadline exceeded" (or request timed out, or whatever makes sense as error message))

### Additional contract requirements

When an update fails, the message sent to Uptime Kuma must be the actual failure
message (for example `context deadline exceeded`), not `OK`. If the failure
message is empty or consists only of whitespace, a non-empty fallback message
must be sent instead. The exact wording of this fallback is not specified, but it
must not be `OK`.
