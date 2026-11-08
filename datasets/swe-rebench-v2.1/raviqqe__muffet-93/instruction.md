Recognize <a href="#name"> as creating a valid link target
Muffet complains `id #mozTocId468501 not found` when it sees my site link to:

http://www.clearskyinstitute.com/xephem/help/xephem.html#mozTocId468501

Yet the link works, jumping to the correct section of the page. It appears that muffet might not yet know about link targets created with `<a href="#name">`? Adding that knowledge would help reduce its noise when run against links whose sites use them. Thanks!

### Additional contract requirements

A URL fragment is valid when the fetched HTML document contains a matching `id` attribute on an element, or a matching `name` attribute on an `<a>` element. Links to either kind of target must be accepted.
