Inner functions documented like methods
The function `readBody` defines two inner functions. These are private helpers and didn't used to appear in pydoctor's output. Now they do, which is a bit confusing:

![image](https://user-images.githubusercontent.com/43662/82702851-a1c63300-9c27-11ea-9c0f-261256aff618.png)

Compare:

- [19.10.0](https://twistedmatrix.com/documents/19.10.0/api/twisted.web.client.readBody.html)
- [20.3.0 rendering](https://twistedmatrix.com/documents/20.3.0/api/twisted.web.client.readBody.html)
