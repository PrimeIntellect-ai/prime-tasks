Nested resources?
Hey there. I've been trying to use this library to serialise some classes in `getServerSideProps` in a Next.js app, but either I'm misunderstanding the aims of this library or I can't see it deserialising nested classes?

I've created a [simple recreation here](https://codesandbox.io/s/superjson-nested-recreation-ti3h7?file=/src/index.ts) (check the console output).

Some steps:
- Given an instance of a class A, of which an attribute is itself an instance of a class B
- `stringify` the instance
- `parse` the instance
- The top level instance of class A has been hydrated, but the nested attribute of type class B is a plain object, when it should be an instance of class B

Please let me know if I'm missing something, and thanks for the OSS!
