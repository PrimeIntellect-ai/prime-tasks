Redirect aliased badges to the canonical form
In #2333 I replaced an old route with a redirect.

As I wrote there:

> In the case of URLs which have permanently changed, an approach I’d like to try is issuing a 301 Redirect.
>
> The benefit is that if a user pastes the URL into the address bar while they are previewing or editing it, the browser will replace the address with the corrected URL when it loads. I figure this will cause some people to update their URLs with no effort, simply because they previewed the badge in their browser, and others to change over, if they notice it.
>
> We incur a slight cost, which is a second request. However many browsers cache the 301’s indefinitely, and we can set an effectively infinite cache duration so the CDN and most other downstream caches will keep them a long time. And handling the redirect is extremely cheap.
>
> This is a nice way to preserve backward compatibility of old routes without having to complicate the new route, such as in the case of vso -> azure-devops. For maintenance purposes, the route that redirects can effectively be treated separately.
>
> It’s also a nice, gentle, and confidence-inspiring way to signal that users should update their URLs.

Some possibilities:

- [ ] vso
- [ ] Wordpress stars
- [ ] snap-ci
- [ ] codacy?

Others?

### Additional contract requirements

- Requests to legacy VSO build and release badge routes must respond with permanent HTTP 301 redirects to their corresponding Azure DevOps build and release badge routes. Preserve the organization, project, definition, optional build branch, and release environment in the destination.
