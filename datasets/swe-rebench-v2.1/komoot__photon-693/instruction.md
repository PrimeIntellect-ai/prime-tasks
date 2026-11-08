Additional languages & v0.4.0 - Possible regression
With Photon 0.3.5, in order to customize language list, you only add to specify your list at import step (with `-languages` attribute).

Then, when starting Photon, you didn't have to provide language list anymore. Photon fetched list from internal `DATABASE_PROPERTIES` ES document.

With 0.4.0, this no longer works. You need to specify language list a second time, when starting Photon instance. Otherwise you're back with default language list (or more precisely, intersection between default list and list defined at import).

I think this has been introduced in 5290f8be. [HIDDEN]

Looks like a regression to me

Thanks

### Additional contract requirements

- When a nonempty language list is explicitly supplied at runtime, Photon must restrict API search results to languages in that list.
