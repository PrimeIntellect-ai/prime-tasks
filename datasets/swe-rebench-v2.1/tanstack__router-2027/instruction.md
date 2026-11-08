Path parameter with value 0 is ignored
### Describe the bug

`<Link
          to={'/employee/$id'}
          params={{
            id: 0,
          }}
        >
          Employee with id 0
        </Link>`

With route:

`export const Route = createFileRoute('/employee/$id')({
  component: AboutComponent,
});`

Since a recent update (1.38.1 -> 1.45.10), this link generates: `/employee` while it used to generate `/employee/0`


`<Link
          to={'/employee/$id'}
          params={{
            id: 5,
          }}
        >
          Employee with id 5
        </Link>`
Still correctly generates  `/employee/5`



### Your Example Website or App

https://stackblitz.com/edit/tanstack-router-jnrhtc?file=src%2Froutes%2F__root.tsx

### Steps to Reproduce the Bug or Issue

- Click on 'About with id 0'
- Notice it renders "Not found" because the link does not include the parameter

### Expected behavior

Path parameters should support the number 0 as we use index based routing in a List->Detail view for entities that don't have a uuid.

### Screenshots or Videos

_No response_

### Platform

- Browser: Chrome



### Additional context

Why I need this:
I use react-hook-form's fieldarray to let the user modifiy an array of 'things'. When the user clicks the 'add thing'
 button I add a 'thing' and navigate to /mypage/things/0 to let the user enter the thing's details.
