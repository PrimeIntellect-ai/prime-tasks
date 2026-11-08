Resolution of "current" IG dependencies broken
Changes in the the CI Build infrastructure have caused the resolution of "current" IGs to fail.  For example, if your package.json declares the following dependencies:
```json
  "dependencies": {
     "hl7.fhir.r4.core": "4.0.1",
     "hl7.fhir.uv.vhdir":"current"
  },
```
Then running SUSHI will now issue these errors:
```
error: Failed to load hl7.fhir.uv.vhdir#current
error: 404 - <html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx/1.17.8</center>
</body>
</html>

error: Failed to add hl7.fhir.uv.vhdir:current to ImplementationGuide instance.  Could not determine its canonical URL from the FHIR cache.
```

More on the changes that caused this:
https://chat.fhir.org/#narrow/stream/179165-committers/topic/Build.20Problem/near/187594182

### Additional contract requirements

A dependency declared with version `current` must be resolved and its FHIR package resources loaded into the definitions. The resolved ImplementationGuide's canonical URL must be available so SUSHI can add that dependency to the generated ImplementationGuide.
