Extra backslashes before spaces in run script phases names
xcbeautify prints a `\` before each whitespace in the names of my "Run Script" build phases.

For example :

```
❯ xcodebuild build -showBuildTimingSummary -workspace Redacted.xcworkspace -scheme Redacted-Debug | xcbeautify
[NotificationExtension] Running script Nullability\ Check
[NotificationExtension] Processing Info.plist
Signing Redacted.NotificationExtension.appex (in target: NotificationExtension)
[Pods-Redacted] Compiling Pods-Redacted-dummy.m
[Pods-Redacted] Building library libPods-Redacted.a
[ShareExtension] Processing Info.plist
Signing Redacted.ShareExtension.appex (in target: ShareExtension)
[Redacted] Running script [CP]\ Check\ Pods\ Manifest.lock
[Redacted] Running script Nullability\ Check
[Redacted] Running script Error\ codes\ check
[Redacted] Running script Linters
[Redacted] Compiling ISConsultationViewController.m
[Redacted] Compiling ISNewDocumentViewController.m
[Redacted] Linking Redacted-Debug
[Redacted] Compiling Consultation.storyboard
[Redacted] Processing Info.plist
[Redacted] Copying Redacted.ShareExtension.appex
[Redacted] Copying Redacted.NotificationExtension.appex
[Redacted] Running script [CP]\ Embed\ Pods\ Frameworks
[Redacted] Running script [CP]\ Copy\ Pods\ Resources
[Redacted] Running script Validate\ Payment\ Pickers\ XML
Signing Redacted-Debug.app (in target: Redacted)
Signing (3 tasks) | 24.000 seconds
Build Succeeded
```

I can probably look at this when I have more time and submit a PR.
