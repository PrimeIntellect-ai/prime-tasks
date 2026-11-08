reject does not fail if argument is of the wrong type
I expected the following test to fail:
```javascript
it('should fail', async () => {
        const promise = Promise.reject(new Error('some error message'));
        await expect(promise).to.reject(Error, {});
        await expect(promise).to.reject(Error, []);
        await expect(promise).to.reject(Error, null);
        await expect(promise).to.reject(Error, undefined);
        await expect(promise).to.reject(Error, NaN);

});
```
But surprisingly it does not. From the documentation, it is clear that the second argument to `reject()` needs to be a string or a regex, but would it not be safer to make the test fail if that is not the case?
