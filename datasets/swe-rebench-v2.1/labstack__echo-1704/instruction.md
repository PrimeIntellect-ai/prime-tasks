Add form field support for JWT middleware
### Issue Description
I've added a new TokenLookup value `form:<name>` to use an HTML form field as a source of JWT tokens. It's trivial and I can open a pull request but I feel like posting an issue first is a good idea.

### Checklist

- [x] Dependencies installed
- [x] No typos
- [x] Searched existing issues and docs

### Rationale
I found it a bit hard to create printed forms securely in my web apps. They're opened in new tabs and contain simple HTML. I need to pass some parameters to them (according to the user's input) as well as the authentication information. Since I use `Authorization: Bearer` header for the latter in the webapp itself I need another way to pass the token without using JS (and it's not possible to open a new tab with a custom HTTP header). So it has to be either a GET or POST parameter.

I really don't want to pass a token as a query parameter because it can easily leak this way. I also don't want to use cookies because it opens a CSRF attack possibility. I ended up with a hidden form input that contains the token (in the JS webapp) that opens a new tab with POST method and passes other user-defined values as query parameters so they're visible and easy to reproduce. But Echo can't extract the token from a form field so I added that and it works just fine.

I also wrote tests (expanded the existing test actually) for this new functionality. Tell me if it's worth adding and I'll post the patch.
