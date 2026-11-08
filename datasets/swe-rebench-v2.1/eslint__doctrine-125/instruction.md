Incorrect parsing of parameter without type
For this code, the `selector` parameter appears to be parsed incorrectly:

```
/**
 * Returns an observable sequence that is the result of invoking the selector on a connectable observable sequence that shares a single subscription to the underlying sequence containing only the last notification.
 * This operator is a specialization of Multicast using a AsyncSubject.
 *
 * @example
 * var res = source.publishLast();
 * var res = source.publishLast(function (x) { return x; });
 *
 * @param selector [Optional] Selector function which can use the multicasted source sequence as many times as needed, without causing multiple subscriptions to the source sequence. Subscribers to the given source will only receive the last notification of the source.
 * @returns {Observable} An observable sequence that contains the elements of a sequence produced by multicasting the source sequence within a selector function.
 */
```

This actually looks like a bug in `doctrine` because the `selector` parameter is missing a name:

```
{ title: 'param',
  description: '[Optional] Selector function which can use the multicasted sourc
e sequence as many times as needed, without causing multiple subscriptions to th
e source sequence. Subscribers to the given source will only receive the last no
tification of the source.',
  type: undefined,
  name: undefined }
```
