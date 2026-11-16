SUSHI should allow artifacts.html to be listed in pages
SUSHI currently checks that every page listed in the `pages` entry in `sushi-config.yaml` actually exists.  But authors may want to list some pages that the IG Publisher generates (such as artifacts.html).  We should either update SUSHI to allow references to _any_ pages (without checking for existence) or at least allow for certain known-to-be-generated pages.

See: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/pages

### Additional contract requirements

- When SUSHI allows a configured page (either because it accepts any page reference or because the page is a known-to-be-generated page such as `artifacts.html`), it must not log an error stating that the page file was not found.
