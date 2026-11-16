[BUG] DELETE missing param details
**Describe the bug**
It seems like DELETE does not convey the param set in the documentation.

**To Reproduce**

The object and endpoint documentation:

```
/**
 * Logout format to send
 * @typedef {object} Logout
 * @property {string} token.required - Access token for user
 */

/**
 * DELETE /logout
 * @summary Log user out of the system
 * @param {Logout} request.body.required - User access and refresh token
 * /
```

**Expected behavior**
The above should show the params field with the request.body detail, but it only shows an empty area.

Changing DELETE to POST brings up the correct expected view.

This currently only happens with DELETE. All other GET and POST behave as expected with the same settings above.

**Desktop:**
 - OS: OSX
 - Version 10.14.6

**Additional context**

Using the following on a TypeScript code base:
- "express-jsdoc-swagger": "^1.6.3",
- "swagger-ui-express": "^4.1.6"
