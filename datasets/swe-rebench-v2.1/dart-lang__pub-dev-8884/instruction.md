`pub.dev/<package_name>` not found page should provide relevant actions
Right now navigating to `pub.dev/<package_name>` leads to a 404 not found page. However, it's quite likely someone navigating to this path with a valid package name wants to visit that package's page.

Rather than just listing possible next steps, I think we could provide two more prominent buttons:

1. A button to go directly to searching with the same query.
2. If a package with a matching name does exist, additionally add a button that goes directly to that package's page.

An alternative or addition to **1** could be pre-filling the search bar.
