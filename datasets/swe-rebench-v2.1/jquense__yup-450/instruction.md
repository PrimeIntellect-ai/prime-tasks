Throws error when there's none
Hi, I do my validation on a controller and I test it with Jest. This is the exception thrown:

```
ValidationError {
      name: 'ValidationError',
      value:
       { companyName: 'TTT Company name',
         companyAddress: 'TTT Company address',
         companyCity: 'TTT Company city',
         companyZipcode: 'G0G0G0',
         firstname: 'TTT firstname',
         lastname: 'TTT lastname',
         tel: '418-999-9999',
         email: 'TTTemail@myadress.com',
         password: '!A1234567!',
         passwordConfirmation: '!A1234567!',
         rbq: 'rbq12345678',
         neq: 'neq12345678',
         tvq: 'tvq12345678',
         tps: 'tps12345678',
         cognitoSub: 'cognito sub',
         subscribeEmail: true },
      path: undefined,
      type: undefined,
      errors:
       [ 'companyZipcode must match the following: "/([A-Z]\\d[A-Z]\\s?\\d[A-Z]\\d)/gi"' ],
      inner:
       [ ValidationError {
           name: 'ValidationError',
           value: 'G0G0G0',
           path: 'companyZipcode',
           type: undefined,
           errors: [Array],
           inner: [],
           message:
            'companyZipcode must match the following: "/([A-Z]\\d[A-Z]\\s?\\d[A-Z]\\d)/gi"',
           params: [Object] } ],
      message:
       'companyZipcode must match the following: "/([A-Z]\\d[A-Z]\\s?\\d[A-Z]\\d)/gi"' }
```

It been thrown on the second part of my test suite. The two are exactly the same, but the second fails.

```
describe('ContactsController', () => {
  test('method create creates a company correctly', async function(done) {
    const client = new AxiosClient({})

    // override Axios post to return mocked response
    mockAxios.post = jest
      .fn()
      .mockImplementationOnce(() =>
        Promise.resolve(ContactCreationTransformer_responseCompanyData)
      )
      .mockImplementationOnce(() =>
        Promise.resolve(ContactCreationTransformer_responseContactData)
      )

    const validator = new DataValidator(ContactCreationSchema)
    const transformer = new ContactCreationTransformer([
      'companyName',
      'companyAddress',
      'companyCity',
      'companyZipcode',
      'firstname',
      'lastname',
      'tel',
      'email',
      'password',
      'passwordConfirmation',
      'rbq',
      'neq',
      'tvq',
      'tps',
      'cognitoSub',
      'subscribeEmail',
    ])

    const controller = new ContactsController(client, validator, transformer)
    const contact = await controller.create(ContactCreationTransformer_rawData)

    expect(mockAxios.post).toHaveBeenCalledTimes(2)
    expect(contact).toEqual(ContactCreationTransformer_transformedResponseData)

    done()
  })

  test('method create throws on error', async function(done) {
    const client = new AxiosClient({})

    // override Axios post to return mocked response
    mockAxios.post = jest
      .fn()
      .mockImplementationOnce(() =>
        Promise.resolve(ContactCreationTransformer_responseCompanyData)
      )
      .mockImplementationOnce(() =>
        Promise.resolve(ContactCreationTransformer_responseContactData)
      )

    const validator = new DataValidator(ContactCreationSchema)
    const transformer = new ContactCreationTransformer([
      'companyName',
      'companyAddress',
      'companyCity',
      'companyZipcode',
      'firstname',
      'lastname',
      'tel',
      'email',
      'password',
      'passwordConfirmation',
      'rbq',
      'neq',
      'tvq',
      'tps',
      'cognitoSub',
      'subscribeEmail',
    ])

    const controller = new ContactsController(client, validator, transformer)
    const contact = await controller.create(ContactCreationTransformer_rawData)

    expect(mockAxios.post).toHaveBeenCalledTimes(2)
    expect(contact).toEqual(ContactCreationTransformer_transformedResponseData)

    done()
  })
})
```

And this is is the regex to validate `companyZipcode` without the escaped backslashes

`/([A-Z]\d[A-Z]\s?\d[A-Z]\d)/gi`

What is going on? Did I forgot to reset the schema or something?

It do this on every second test case using validation on Zipcode/Postal Code.

Thank you very much for your help
