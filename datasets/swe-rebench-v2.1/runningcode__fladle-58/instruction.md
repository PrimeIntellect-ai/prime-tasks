Question: Do I have to set serviceAccountCredentials?
On Flank docs I see that I can set service account credentials locally and for CI using some env vars https://github.com/TestArmada/flank#authenticate-with-a-service-account

If I'm using Fladle can I do this instead of supplying `serviceAccountCredentials("${project.file(....)` in build.gradle?

### Additional contract requirements

When `serviceAccountCredentials` is not set (and `projectId` is set), the Flank execution task (`execFlank`) must leave the `GOOGLE_APPLICATION_CREDENTIALS` environment variable untouched, so that credentials supplied through the environment are used instead of `serviceAccountCredentials(...)`. It must also not require a service-account credentials file to exist.
