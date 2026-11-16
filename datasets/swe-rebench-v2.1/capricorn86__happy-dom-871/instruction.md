DOMParser ignoring semicolons in hexadecimal html entities
**Describe the bug**
Using DOMParser for a string with characters such as `&lt;` or `&gt;` does not remove the semicolon as does the browser version

**To Reproduce**
Steps to reproduce the behavior:
1. Create a test for this function:
```ts
function htmlDecode(input: string): string {
  const doc = new DOMParser().parseFromString(input, "text/html");
  return doc.documentElement.textContent;
}
```
Like so:
```ts
it("should decode HTML entities", () => {
  expect(htmlDecode('&#x3C;div&#x3E;Hello, world!&#x3C;/div&#x3E;')).toBe(
    '<div>Hello, world!</div>',
  );
});
```

![image](https://user-images.githubusercontent.com/61510135/233091744-694cedf9-6664-4d3f-b110-1474748f3a39.png)

**Expected behavior**
The DOMParser should remove the semicolons, as does the browser:
![image](https://user-images.githubusercontent.com/61510135/233649551-570788c6-8f63-436b-a742-876696d058f5.png)

**Screenshots**
Added inline

**Device:**
 - OS: Windows 10
 - Browser Chrome/Vitest
 - Version Vitest 0.30.1, happydom 9.8.0

**Additional context**
Add any other context about the problem here.
