n.compareDocumentPosition is not a function
Hi there 👋🏻 ,

I hope it is the right place to ask, and I apologize if not. I'm currently using `happy-dom` with `vitest` but I'm facing the following error:

![image](https://user-images.githubusercontent.com/11817371/176379353-d55400e2-ca84-4189-82a4-6bc6831b8627.png)

```text
Binaries:
    Node: 16.15.1 - /usr/bin/node
    npm: 8.11.0 - /usr/bin/npm
  npmPackages:
    happy-dom: 5.3.4 => 5.3.4
    vite: 2.9.13 => 2.9.13
    vitest: 0.16.0 => 0.16.0
```

Reproduction repo: [smarlhens/vite-vitest-happy-dom-compare-document-position-is-not-a-function](https://github.com/smarlhens/vite-vitest-happy-dom-compare-document-position-is-not-a-function)

You can check using `jsdom` with `vitest` by switching `test.environment: 'jsdom'` in `vite.config.ts`.


Thanks in advance for your help, wish you a nice day sunny

### Additional contract requirements

- Add a public method `Node.compareDocumentPosition(otherNode: INode): number` on `Node` (module `src/nodes/node/Node.ts`). It accepts any node and returns a numeric bit-field describing the relative document order and containment relationship between the two nodes, using the standard DOM values: `DOCUMENT_POSITION_DISCONNECTED` = 1, `DOCUMENT_POSITION_PRECEDING` = 2, `DOCUMENT_POSITION_FOLLOWING` = 4, `DOCUMENT_POSITION_CONTAINS` = 8, `DOCUMENT_POSITION_CONTAINED_BY` = 16 and `DOCUMENT_POSITION_IMPLEMENTATION_SPECIFIC` = 32.
