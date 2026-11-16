[🐛] 🔥 Firebase Auth module requires REVERSE_CLIENT_ID for iOS even when only using email authentication
## Issue

<!-- Please describe your issue here --^ and provide as much detail as you can. -->
<!-- Include code snippets that show your usages of the library in the context of your project. -->
<!-- Snippets that also show how and where the library is imported in JS are useful to debug issues relating to importing or methods not found issues -->

The @react-native-firebase/auth module is requiring a REVERSE_CLIENT_ID field in the GoogleService-Info.plist file during iOS prebuild, even though I'm only using email/password authentication and not Google Sign-In.

When running npx expo prebuild --platform ios, I get this error:

```
✖ Prebuild failed
Error: [ios.infoPlist]: withIosInfoPlistBaseMod: [@react-native-firebase/auth] Failed to parse your GoogleService-Info.plist. Are you sure it is a valid Info.Plist file with a REVERSE_CLIENT_ID field?
```

This is forcing me to enable Google Sign-In in Firebase (which I don't need or want to use) just to get the REVERSE_CLIENT_ID field in my configuration file.

### Javascript

<details><summary>Click To Expand</summary>
<p>

#### `package.json`:

```json
{
  "dependencies": {
    "@react-native-firebase/app": "^x.x.x",
    "@react-native-firebase/auth": "^x.x.x",
    "expo": "^x.x.x",
    "react-native": "x.x.x"
  }
}

```

Authentication code only uses email/password auth
```
const handleSignup = () => {
    auth()
      .createUserWithEmailAndPassword(email, password)
      .then(() => {
        // Signed in
        Alert.alert("Success", "Account created successfully!");
        navigation.navigate("Login");
      })
      .catch(error => {
        if (error.code === "auth/email-already-in-use") {
          Alert.alert("Error", "That email address is already in use!");
        } else if (error.code === "auth/invalid-email") {
          Alert.alert("Error", "That email address is invalid!");
        } else {
          Alert.alert("Error", error.message);
        }
      });
  };
```

The REVERSE_CLIENT_ID field is missing from my GoogleService-Info.plist file. Firebase did not generate one for me because I'm not using Google Sign-In, but the module needs it anyway.

### Environment
# Platform that you're experiencing the issue on:

iOS

### react-native-firebase version you're using that has this issue:

Latest version

### Firebase module(s) you're using that has the issue:

@react-native-firebase/auth

### Are you using TypeScript?

No

### Expected Behavior
The @react-native-firebase/auth module should only validate for configuration fields that are necessary for the authentication methods I'm actually using. Since I'm only using email/password authentication and not Google Sign-In, it shouldn't require the REVERSE_CLIENT_ID field to be present in my GoogleService-Info.plist file.

### Actual Behavior
The module is requiring the REVERSE_CLIENT_ID field to be present during prebuild, even though I'm not using Google Sign-In. This forces me to enable Google Sign-In in Firebase (which I don't need) just to get the REVERSE_CLIENT_ID field in my configuration file.

### Workarounds
The only workaround I've found is to enable Google Sign-In in Firebase, download a new GoogleService-Info.plist file that includes the REVERSE_CLIENT_ID field, and then use that for building - even though I don't actually use Google Sign-In in my app.
