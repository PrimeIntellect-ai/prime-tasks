Allowing comments
Hi there.

I was looking for the reason why my comments are being sanitized and I found that they are simply ignored by default: https://github.com/microcosm-cc/bluemonday/blob/master/sanitize.go#L228

I bet that for most of the cases comments are not necessary, but in my case, they are essential.

My question is: do you guys think that adding AllowComments method (false by default) is a good, safe idea and is worthy of PR?
