Codesigning error lost
Origin log:

```text
/Users/xxxxx/Example/Pods/Pods.xcodeproj: warning: The iOS deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 9.0, but the range of supported deployment target versions is 11.0 to 16.0.99. (in target 'XXPay' from project 'Pods')
/Users/xxxxx/Example/AAAA.xcodeproj: warning: The iOS deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 9.0, but the range of supported deployment target versions is 11.0 to 16.0.99. (in target 'AAAA_Example' from project 'AAAA')
/Users/xxxxx/Example/AAAA.xcodeproj: error: The file "/Users/xxxxx/AAAA/Example/configs/domestic/ueaws/app.entitlements" could not be opened. Verify the value of the CODE_SIGN_ENTITLEMENTS build setting for target "AAAA_Example" is correct and that the file exists on disk. (in target 'AAAA_Example' from project 'AAAA')
```

But no error show me from xcbeautify

### Additional contract requirements

- For the input `/path/to/project.xcodeproj: error: No signing certificate "iOS Distribution" found: No "iOS Distribution" signing certificate matching team ID "xxxxx" with a private key was found. (in target 'target' from project 'project')`, output `[x] error: No signing certificate "iOS Distribution" found: No "iOS Distribution" signing certificate matching team ID "xxxxx" with a private key was found. (in target 'target' from project 'project')` and classify it as an error.

- For any input line of the form `<path>.xcodeproj: error: <message>`, output `[x] error: <message>` (the `.xcodeproj` path is not part of the output) and classify it as an error.
