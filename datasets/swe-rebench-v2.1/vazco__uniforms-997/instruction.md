[QUESTION]: Can't convert string to object
Hi, I seem to be experiencing a weird issue.

I am using a GraphQL schema with my form and I have a field that is a String type.
In my model, I load the string with a value.
I have a Select that is a custom component that allows me to select a different value and the selected value returned is an object.

When I change the selection the field in the model is updated correctly from a string to an object, and in the transform I can change it when I submit my form.

The issue I am having is when I use the formRef that I passed to AutoForm, and call onChange to change my field value to an object, it gives me this error:

> Cannot use 'in' operator to search for 'name' in some string

It might be related to: https://github.com/vazco/uniforms/issues/960

You can see an example here:

https://codesandbox.io/s/cant-convert-string-to-object-with-onchange-o1o7q

I am using latest uniforms version.

I am triggering the change with `useEffect` in the code on line `116`.

In this example, I did not put a Select as the field, I simply wanted to show the error message.

Hope you can help.
Let me know if I am not being clear in my description.

Thanks!
