ern code-push release doesn't recognize custom application name in cauldron
In cauldron.json file, I specified appName like below. But ern doesn't recognize this and takes as MyAppAndroid. And this leads to Codepush 404 error.

Should resolve like My-Team/MyAppAndroid

```
{
  "name": "Cauldron",
  "nativeApps": [
    {
      "name": "MyApp",
      "platforms": [
        {
          "name": "android",
          "config": {
            "codePush": {
              "appName": "My-Team/MyAppAndroid"
            }
          }
        }
      ]
    }
  ],
  "schemaVersion": "3.0.0"
}


```
