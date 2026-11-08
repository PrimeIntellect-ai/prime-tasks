/ char should not be allowed in wallet name
**Expected behavior**

entering a `/` char in the wallet name should be disallowed by the javascript.

**Actual behavior**

Wallet creation in bitcoin core will fail because / cannot be in a directory name

**Steps to reproduce the problem**
  1. Create a new wallet
  2. Put a / in the name
  3. Click create

**Specifications**
  - Version: 016
  - Platform: Linux
  - Browser: Firefox

**Additional context**

![image](https://github.com/joinmarket-webui/jam/assets/106188942/6babd4bd-eac7-43a5-a20e-8cf32f4d6c20)

### Additional contract requirements

- A wallet name containing `/` must be rejected by the client-side creation form and must not be submitted for creation.
- When a wallet name is invalid, display the validation message `create_wallet.feedback_invalid_wallet_name`.
