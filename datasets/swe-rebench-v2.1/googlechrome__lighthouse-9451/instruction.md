Offline pass doesn't always go offline
#### Provide the steps to reproduce
1. Run LH on https://www.bhphotovideo.com/


#### What is the current behavior?

Lighthouse reports that the start URL does not load offline but the current page does.

You can observe that in the offline pass, the desktop version of the page is loaded, and upon inspecting lighthouse internals see that the `fromServiceWorker` and `fromDiskCache` flags on all network requests are `false`. This shouldn't be possible when offline.

#### What is the expected behavior?

Lighthouse reports that the start URL loads offline. A page like the below should be visible during the offline pass, not the desktop version of the site.

![image](https://user-images.githubusercontent.com/2301202/61826719-a1eb7b80-ae28-11e9-88c7-6145188e8763.png)


#### Environment Information
* Affected Channels: CLI
* Lighthouse version: 5.2.0
* Node.js version: v10.15.3
* Operating System: macOS

**Related issues**
brought over from https://github.com/GoogleChrome/lighthouse/issues/2688#issuecomment-514738794

### Additional contract requirements

- While Lighthouse checks whether the start URL loads offline, the browser must remain offline for the entire check, and the browser must be brought back online once the check completes.
- The start URL check reports the HTTP status code returned for the start URL when it is served by a service worker, and reports `-1` when the start URL cannot be loaded offline for any reason.
- When the reported status code is `-1`, the result may include a human-readable `explanation` string describing why the start URL could not be loaded offline.
