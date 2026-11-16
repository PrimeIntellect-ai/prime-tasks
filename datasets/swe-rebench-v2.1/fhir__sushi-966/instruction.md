Automatically infer canonical URI of dependency from package.json
SUSHI needs a URI for each dependency IG so that it may populate `ImplementationGuide.dependsOn`. However, certain packages do not have ImplementationGuide resources, so we cannot get a canonical URI. In this case, we require that the user manually specify the canonical in the `dependencies` object in `sushi-config.yaml`. We could instead try to infer the URI from the `package.json` which should be present in the package. This may present its own problems, and we should investigate and test some different packages before adding support.

See this thread for details: https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/ImplementationGuide.3A.20ImplementationGuide.20instance.20misses.20url.
