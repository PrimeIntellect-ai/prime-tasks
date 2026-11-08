Luigi Container: warning is logged in the browser console for non-luigi window messages
<!-- Thank you for your contribution. Before you submit the issue:
1. Search open and closed issues for duplicates.
2. Read the contributing guidelines: https://github.com/SAP/luigi/blob/main/CONTRIBUTING.md
-->

**Description**
Luigi container listens to every message from the microfrontend iframe and process it as a potential Luigi Container event. In our application some 3rd party scripts actively use `window.postMessage`. Since Luigi tries to process all the messages, there is a warning logged in the browser console every time there is a message not known by Luigi.

<!-- Provide a clear and concise description of the problem.
Describe where it appears, when it occurred, and what it affects.  -->

<!-- Provide relevant technical details such as the browser name and version, or the operating system. -->

**Expected result**
No warning in the browser console. If Luigi container cannot recognize the message received, there is no need for `console.warn` here - https://github.com/SAP/luigi/blob/main/container/src/services/container.service.ts#L180

<!-- Describe what you expect to happen. -->

**Actual result**
Warning messages in the browser console:
<img width="340" alt="Screenshot 2024-06-05 at 16 35 01" src="https://github.com/SAP/luigi/assets/169250132/24358b59-9a78-4534-8f93-49819c49278e">

<!-- Describe what happens instead. -->

**Steps to reproduce**
Can be reproduced by sending any custom message from iframe to a host application. Custom message should not contain `event.data.msg` or its value should be something different from well-known Luigi Container events listed in https://github.com/SAP/luigi/blob/main/container/src/constants/internal-communication.ts

<!-- List the steps to follow to reproduce the bug. Attach any files, links, code samples, or screenshots that could help in investigating the problem. -->

**Troubleshooting**
`-`

<!-- Describe the steps you have already taken to solve the issue. -->
