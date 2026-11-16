Changes to httpx SSL cert handling
Hi,

I've just tried out bimmer_connected as a workaround for evcc.io not supporting the new captcha. I have bimmerconnected working on my MacBook, but I need to get it running on my Raspberry Pi for evcc to be able to use it.

On my RPi, when I run:

bimmerconnected status MYEMAIL MYPASS -v MYVIN rest_of_world --json --hcaptcha THE_CAPTURE_TOKEN

I get:

Traceback (most recent call last):
  File "/usr/local/bin/bimmerconnected", line 5, in <module>
    from bimmer_connected.cli import main
  File "/usr/local/lib/python3.9/dist-packages/bimmer_connected/cli.py", line 16, in <module>
    from bimmer_connected.account import MyBMWAccount
  File "/usr/local/lib/python3.9/dist-packages/bimmer_connected/account.py", line 11, in <module>
    from bimmer_connected.api.authentication import MyBMWAuthentication
  File "/usr/local/lib/python3.9/dist-packages/bimmer_connected/api/authentication.py", line 44, in <module>
    class MyBMWAuthentication(httpx.Auth):
  File "/usr/local/lib/python3.9/dist-packages/bimmer_connected/api/authentication.py", line 57, in MyBMWAuthentication
    verify: httpx._types.VerifyTypes = True,
AttributeError: module 'httpx._types' has no attribute 'VerifyTypes'

I've Googled that error and don't get any results. I have not done any Python for a very, very long time so I'm out of my depth here.

python -V reports:

Python 3.9.2

and it appears I have version 0.28.0 of httpx. I randomly tried 0.24.0 as well but it makes no difference.

_Originally posted by @pdonovan in https://github.com/bimmerconnected/bimmer_connected/discussions/687_
