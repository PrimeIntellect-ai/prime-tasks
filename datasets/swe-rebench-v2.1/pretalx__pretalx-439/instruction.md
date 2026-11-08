Speaker Submission Confirm URL - 404 Response
## Expected Behavior
The mailed submission confirm links should redirect to the login page if the speaker is not
logged in.

## Current Behavior
404 Error:
```
WARNING 2018-05-27 09:22:30,574 django.request base Not Found: /EVENT/me/submissions/CODE/confirm
```

## Steps to Reproduce (for bugs)
Open link: /EVENT/me/submissions/CODE/confirm without permission (not logged in)

## Your Environment
<!--- Include as many relevant details about the environment you experienced the bug in -->
* Version used: 0.6.1
* Environment name and version: Chrome 66
* Operating System and version (desktop or mobile): Desktop
* Link to your project: https://fahrplan.podstock.de/
