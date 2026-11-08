usePagination shows negative page numbers when showPages > totalPages
### Version number

1.1.2

### Description of the bug

When `showPages` is greater than `totalPages`, `usePagination` returns a list containing negative page numbers.

### Steps To Reproduce

https://codesandbox.io/p/sandbox/c29d8p

### Additional Information

This can be fixed from the consumer by adding a conditional, but is negative numbers a good default?

```ts
const totalPages = 1 // some arbitrary which comes from somewhere else

const { pages, prevButtonProps, nextButtonProps } = usePagination({
    currentPage,
    setCurrentPage,
    onChange: handlePageChange,
    totalPages,
    showPages: totalPages > 1 ? 5 : 1,
  });
```
