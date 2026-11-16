SSR prefetching (hydration/dehydration) with NextJS and client side routing to the same route.
**Describe the bug**

Not sure if this is a bug or if I'm doing something incorrectly but when using SSR hydration/dehydration prefetching based on the [docs](https://react-query.tanstack.com/docs/guides/ssr#integrating-with-nextjs), the first request will set initial data for a query correctly, but when routing to the same route but with a different param the cache isn't updated with the new prefetched value.

**To Reproduce**
Steps to reproduce the behavior:
1. Go to https://ctwew.sse.codesandbox.io/set1
2. Open up the dev tools and see that the data returned from getServerSideProps and the data displayed is the same.
3. Click on toggle set, this will perform a client side route change and will call getServeSideProps as an api call.
4. You will notice that the data onscreen will still have "dataSet: set1", the url will be "/set2". However if you check the console you will see that the data contains "dataSet: set2"

**Expected behavior**
I would expect the data from getServerSideProps to update the cache and the components using the data to be rerendered with the correct values.

**Screenshots**
https://codesandbox.io/s/amazing-paper-ctwew?file=/pages/%5BdataSet%5D.js

Data returned from getServerSideProps on the initial page load.
![Screenshot 2020-09-02 at 11 13 28](https://user-images.githubusercontent.com/33291351/91969007-669acc00-ed0d-11ea-95e9-41f45860caf7.png)

Data returned from getServerSideProps on the route change.
![Screenshot 2020-09-02 at 11 13 42](https://user-images.githubusercontent.com/33291351/91969074-7c0ff600-ed0d-11ea-9feb-e2a92cfc3e3b.png)


**Desktop (please complete the following information):**
 - OS: macOs
 - Browser: chrome
 - Version: 2.13.1


**Additional context**
I did notice the force option for the prefetch query options and have tried it with "force: true" but that didn't work either.
