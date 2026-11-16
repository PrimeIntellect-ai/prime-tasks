Initial value for deeply nested forms when adding a field.
Is there any way I could add an initial value for nested form but only when I want to add it?
````js
export const fields = [
  "content",
  "children[].firstname",
  "children[].lastname"
];
````
And when I call `children.addField()` I want firstname to have an initial value. Looking into the code I see that addField receives 2 optional arguments and one of them is `value`, but if I try to use it

````js
children.addField({firstname: 'Tom', lastname: 'Whatever'})
````

it doesn't seem to work. I'm not sure I'm doing this right.
I'm using v3.1.7.
