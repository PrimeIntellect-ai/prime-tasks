Feature Request: bundle()->dequeue
### Terms

- [X] I have read the [guidelines for Contributing to Roots Projects](https://github.com/roots/.github/blob/master/CONTRIBUTING.md)
- [X] This request is not a duplicate of an existing issue
- [X] This is not a personal support request that should be posted on the [Roots Discourse](https://discourse.roots.io/) community

### Summary

Function to dequeue loaded files (js / css)

### Motivation

#### Why are we doing this?

Some pages should not have the JS / CSS used on the rest of the site (for example a redirection page for Internet Explorer on the front, or a style applied only to some pages and not to others in the back-office)

#### What is the expected outcome?

Do not load the JS / CSS

#### Potential conflicts / foreseeable issues

None ?


### Additional Context

_No response_

### Additional contract requirements

- Add a public method `dequeue()` on `Roots\Acorn\Assets\Bundle` that dequeues both the bundle's CSS and JavaScript handles.
- Add a public method `dequeueCss()` on `Roots\Acorn\Assets\Bundle` that dequeues each CSS handle registered by the bundle via WordPress `wp_dequeue_style`.
- Add a public method `dequeueJs()` on `Roots\Acorn\Assets\Bundle` that dequeues each JavaScript handle registered by the bundle via WordPress `wp_dequeue_script`.
- Add a public method `when($conditional, ...$args)` on `Roots\Acorn\Assets\Bundle` that accepts a boolean or callable condition, passes any optional arguments to the callable, returns the bundle instance for method chaining, and makes `js()` return an empty collection when the condition is false.
