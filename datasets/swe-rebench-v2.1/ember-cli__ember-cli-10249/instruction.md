Serve app at /rooturl when using the history location type
I noticed that ember-cli started defaulting locationType to history ~a year ago. This is great!

Unlike `auto` location, `history` location supports visiting the bare root url (i.e. no trailing slash) directly. For example, if your config contains `rootURL: '/example/``, with history location the app will work correctly when served at http://localhost/example (e.g. via nginx).

The issue I'm running into is that the ember-cli development server doesn't serve the app at this URL:

<img width="716" alt="image" src="https://user-images.githubusercontent.com/1151810/230393165-b665c85d-35bc-4dfc-b16a-02391f92ac48.png">

I think that we should modify the HistoryMiddleware to serve the app on the bare root url when using the history location type. Somewhere around here: https://github.com/ember-cli/ember-cli/blob/master/lib/tasks/server/middleware/history-support/index.js#L89-L91
