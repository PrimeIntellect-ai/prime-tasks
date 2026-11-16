Clicking a notification marks it as read but doesn't remove it from the app
### 🔍 Is there already an issue for your problem?

- [X] I have checked older issues, open and closed

### 📝 Description

Using the `main` branch, when you click on a notification it automatically gets marked as read, but Gitify doesn't remove the notification until the 60s setInterval gets triggered again

Should we remove the notification on click?

### 🪜 Steps To Reproduce

1. Build & run the app from the `main` branch
2. Click on a notification
3. Wait for the next notifications refresh -> the notification disappears

### ℹ System Info

```Markdown
`main` branch
```


### 📸 Screenshots

_No response_
