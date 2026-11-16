Misleading error message on failed userinfo call
This test literally shows the bad error message: https://github.com/auth0/auth0.js/blob/master/test/web-auth/web-auth.test.js#L765

I am successfully using HS256 wiht auth0.js v9.3.1 and sporadically I see a confusing error log: `Algorithm HS256 is not supported. (Expected algs: [RS256])`

This means my user's internet had issues making the userinfo call. Please make this behaviour more clear!
