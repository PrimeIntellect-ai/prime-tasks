about undefined properties in tsoa request body
## Sorting

* **I'm submitting a ...**
  - [X] bug report
  - [ ] feature request
  - [X] support request

* I confirm that I
  - [X] used the [search](https://github.com/lukeautry/tsoa/search?type=Issues) to make sure that a similar issue hasn't already been submit

## Issue / Question

I have a simple input post body e.g.:
```ts
interface InputDTO {
	firstName?: string;
	lastName?: string;
	email?: string;
	phone?: string;
	birthday?: Date;
	gender?: Gender;
	nationality?: string;
}
 enum Gender {
	Male = 'male',
	Female = 'female'
}

     @Post('/test')
	async test(
		@Request() req,
		@Body() body: InputDTO
	): Promise<{
		userUpdate: { [key: string]: any };
	}> {
		console.log('body', body);
       }
```

and if I call it with "firstName" only, all other properties are stil there, but undefined.
```js
{
  firstName: 'safd',
  lastName: undefined,
  email: undefined,
  phone: undefined,
  birthday: undefined,
  gender: undefined,
  nationality: undefined
}
```

the question is, is this expected? Therefore I cannot distinguish between calling "firstName: undefined" and firstName not provided at all.
The check
```js
if ('firstName' in body) {
    console.log('firstName provided');
}
```
is always true.

## Possible Solution
[HIDDEN]

## Context (Environment)
Version of the library: tsoa@2.5.8
Version of NodeJS: v12.13.0

### Additional contract requirements

- When validating a request body against a model, an optional property absent from the input must not appear in the validated object.
- If an optional property is explicitly present in the input with the value `undefined`, it must remain present with the value `undefined` in the validated object.
