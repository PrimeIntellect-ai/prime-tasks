MSAL python 1.4.2 is no longer able to read from other MSAL caches
**Describe the bug**
MSAL.NET maintains cache consistency tests between libraries. It looks like MSAL.py 1.4.2 update brakes the tests which ensure MSAL .py is able to read the token cache produced by .NET and Java.

After downgrading to MSAL py 1.4.1 (`pip install msal==1.4.1 --force-reinstall`), the tests start passing again.

**To Reproduce**

1. AcquireTokenInteractive with MSAL.NET or with MSAL.Java and save the cache to a file (plaintext)
2. Configure MSAL py to read the cache from the file
3. AcquireTokenSilent with MSAL.Python (using the same scope, client_id etc.)

**Expected behavior**
AcquireTokenSilent should work (i.e. it should fetch the AT, there is no need for RT refresh)

**What you see instead**
GetAccounts returns 1 acconunt, however **AcquireTokenSilent return None.**

**The MSAL Python version you are using**
1.4.2

**Additional context**
Works with 1.4.1

Impact: please do not ship this version to AzCLI or any other partners with whom we do cache sharing!

Note: python test code is [here](https://github.com/AzureAD/microsoft-authentication-library-for-dotnet/blob/d9f182257fceb34d7510502f9f42d91afde5abbe/tests/CacheCompat/CommonCache.Test.MsalPython/TestMsalPython.py#L33)
