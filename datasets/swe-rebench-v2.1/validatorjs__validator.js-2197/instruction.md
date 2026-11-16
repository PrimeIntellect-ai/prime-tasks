isMobilePhone with locale es-CU matches numbers of any length > 8 when the number starts with 5
**Describe the bug**
`isMobilePhone` with locale es-CU matches any string that start with a 5 followed by at least 7 digits. [HIDDEN]


**Examples**
Repl.it demo: https://replit.com/join/vcsakenqug-klaframboise1
<img width="1440" alt="Screenshot 2023-03-03 at 3 51 07 PM" src="https://user-images.githubusercontent.com/6961215/222827052-2e31ebab-660a-48ad-bf63-fbab35d44df6.png">


**Additional context**
Validator.js version: 13.9.0
Node.js version: 18.12.1
OS platform: linux + macOS

### Additional contract requirements

- For locale `es-CU`, `isMobilePhone` must reject strings that extend an otherwise valid number instead of accepting a matching prefix.
