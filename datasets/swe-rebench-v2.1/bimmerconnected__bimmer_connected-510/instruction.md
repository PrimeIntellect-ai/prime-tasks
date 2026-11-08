Vehicle Image Function Returns HTTP Code 424: Failed Dependency
### Describe the issue

After a successful login, all endpoints and functions appear to be working correctly with the exception of the vehicle image function. Calling the vehicle image endpoint for any `carView` other than `VehicleStatus` yields a JSON Body Response:
> `{
	"error": "get_vehicle_image_failure",
	"description": "user does not own VIN"
}`

with a **HTTP Status Code of 424 (Failed Dependency)**

### Expected behavior

The response body of content-type: image/png containing the image for `carView` of the specified `{VIN}`

### Which Home Assistant version are you using?

N/A, Not Using via HA

### What was the last working version of Home Assistant Core?

_No response_

### What is your region?

North America

### MyBMW website

- [X] I can still successfully login to the BMW MyBMW website and the car status is available there.
- [X] I have MyBMW enabled for my vehicle.

### Number of cars

- [ ] I have 2 or more cars linked to the MyBMW account.
- [ ] I have a Mini vehicle linked to my account.

### Output of bimmer_connected fingerprint

```txt
See Fingerprint Data Contribution Discussion Referenced In Additional Information Section Below.
```


### Anything in the logs that might be useful for us?

```txt
DEBUG:asyncio:Using selector: KqueueSelector
DEBUG:bimmer_connected.account:Getting vehicle list
DEBUG:bimmer_connected.account:Getting vehicle list
DEBUG:bimmer_connected.api.authentication:Authenticating with MyBMW flow for North America & Rest of World.
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-ucs/v1/presentation/oauth/config "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: POST https://login.bmwusa.com/gcdm/oauth/authenticate "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: POST https://login.bmwusa.com/gcdm/oauth/authenticate "HTTP/1.1 302 Found"
DEBUG:httpx._client:HTTP Request: POST https://login.bmwusa.com/gcdm/oauth/token "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-vcs/v2/vehicles "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-vcs/v2/vehicles "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-vcs/v2/vehicles/some_redacted_vin/state "HTTP/1.1 200 OK"
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-ics/v3/presentation/vehicles/some_redacted_vin/images?carView=VehicleStatus "HTTP/1.1 200 OK"
vehicle image saved to frontside.png
DEBUG:httpx._client:HTTP Request: GET https://cocoapi.bmwgroup.us/eadrax-ics/v3/presentation/vehicles/some_redacted_vin/images?carView=VehicleInfo "HTTP/1.1 424 Failed Dependency"
Traceback (most recent call last):
  File "/Users/some_user/some_path/bimmer-connected/env/bin/bimmerconnected", line 8, in <module>
    sys.exit(main())
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/bimmer_connected/cli.py", line 286, in main
    loop.run_until_complete(args.func(args))
  File "/opt/homebrew/Cellar/python@3.10/3.10.8/Frameworks/Python.framework/Versions/3.10/lib/python3.10/asyncio/base_events.py", line 649, in run_until_complete
    return future.result()
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/bimmer_connected/cli.py", line 200, in image
    image_data = await vehicle.get_vehicle_image(viewdirection)
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/bimmer_connected/vehicle/vehicle.py", line 266, in get_vehicle_image
    response = await client.get(url, headers={"accept": "image/png"})
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/httpx/_client.py", line 1751, in get
    return await self.request(
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/httpx/_client.py", line 1527, in request
    return await self.send(request, auth=auth, follow_redirects=follow_redirects)
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/httpx/_client.py", line 1614, in send
    response = await self._send_handling_auth(
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/httpx/_client.py", line 1642, in _send_handling_auth
    response = await self._send_handling_redirects(
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/httpx/_client.py", line 1700, in _send_handling_redirects
    raise exc
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/httpx/_client.py", line 1682, in _send_handling_redirects
    await hook(response)
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/bimmer_connected/api/client.py", line 66, in raise_for_status_event_handler
    response.raise_for_status()
  File "/Users/some_user/some_path/bimmer-connected/env/lib/python3.10/site-packages/httpx/_models.py", line 736, in raise_for_status
    raise HTTPStatusError(message, request=request, response=self)
httpx.HTTPStatusError: Client error '424 Failed Dependency' for url 'https://cocoapi.bmwgroup.us/eadrax-ics/v3/presentation/vehicles/some_redacted_vin/images?carView=VehicleInfo'
For more information check: https://httpstatuses.com/424
```


### Additional information

See Discussion #497
### Title
> 2017 BMW 330i (F30) [Vehicle Image Function Returns HTTP Error 424]
### Category
> Fingerprint Data Contributions
