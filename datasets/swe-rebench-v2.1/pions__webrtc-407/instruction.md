CreateOffer and CreateAnswer shouldn't call setLocalDescription
Currently these two methods incorrectly call `setLocalDescription` causing us to deviate from the spec.

This is going to cause user breakage, and we will have to figure out a way a nice way to notify users.
