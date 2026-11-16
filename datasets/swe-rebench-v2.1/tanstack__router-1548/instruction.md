Navigation without to param does not work since 1.30.1
### Describe the bug

I updated to 1.30.1, because fix for bug with path params was introduced and it works fine. But, it broke other thing. Before 1.30.1 I was able to make link, or use navigate(), or throw redirect() without specifing to. I did it, because I only need to change path param(for example language code in path param), but I want to leave user on the same page and it worked fine. Now it ignores new path params and generates href with old params in this case.

### Your Example Website or App

everywhere

### Steps to Reproduce the Bug or Issue

1. Create <Link> component and specify only from and params
2. Press/hover on it. Nothing happens

### Expected behavior

I expected to generate href with new params, but previous path

### Screenshots or Videos

_No response_

### Platform

- OS: all
- Browser: all
- Version: 1.30.1


### Additional context

_No response_

### Additional contract requirements

A link without `to` generates an href for the current route with supplied path parameters applied, retaining unspecified path parameters. A redirect without `to` likewise updates the current route pathname with supplied path parameters while retaining unspecified parameters and the current route hierarchy.
