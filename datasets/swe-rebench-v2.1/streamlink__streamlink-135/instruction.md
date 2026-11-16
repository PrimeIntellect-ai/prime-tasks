younow.com is broken
They have changed the API url to this one:
`https://api.younow.com/php/api/broadcast/info/curId=0/user=`
in:
https://github.com/streamlink/streamlink/blob/master/src/streamlink/plugins/younow.py#L9

It still needs rtmpdump.exe, so it will give you the following error, related to #56
`[cli][error] Could not open stream: Unable to find rtmpdump.exe command`
#81 fixes it, and the plugin works fine.
