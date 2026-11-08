Cannot set version on ValueSet compose.include elements
See this thread for details: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/Specifying.20version.20on.20a.20code.20system.20URI.

We support setting versions using the `|` when fixing codes, but we don't support this when setting the `compose.include` or `compose.exclude` elements on a ValueSet, so it is difficult to set a version.
