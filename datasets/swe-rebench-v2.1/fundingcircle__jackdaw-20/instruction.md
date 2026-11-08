Cannot create record with ConsumerRecordFactory when the key is of type String
When trying to test my topology I stumbled upon a bug. I'm trying to test a topology that groups a stream in time windows. When the topic's `key` is a String, the wrong method in the `ConsumerRecordFactory` is used when using an explicit `time-ms`.

[HIDDEN]

I was able to create another test case for `streams-test` that reproduces the issue:

```clojure
  (testing "windowed-by-time with string keys"
    (let [topic-a (assoc (mock/topic "topic-a") :key-serde (Serdes/String))
          topic-b (assoc (mock/topic "topic-b") :key-serde (Serdes/String))
          driver (mock/build-driver (fn [builder]
                                      (-> builder
                                          (k/kstream topic-a)
                                          (k/group-by-key)
                                          (k/window-by-time (TimeWindows/of 1000))
                                          (k/reduce + topic-a)
                                          (k/to-kstream)
                                          (k/map (fn [[k v]] [(.key k) v]))
                                          (k/to topic-b))))
          publish (partial mock/publish driver topic-a)]

      (publish 1000 "a" 1)
      (publish 1500 "a" 2)
      (publish 5000 "a" 4)

      (let [keyvals (mock/get-keyvals driver topic-b)]
        (is (= 3 (count keyvals)))
        (is (= [0 1] (first keyvals)))
        (is (= [0 3] (second keyvals)))
        (is (= [0 4] (nth keyvals 2))))))
```

### Additional contract requirements

For the string-key reproducer, the key extracted from each windowed result is the original string key `"a"`, so its collected pairs are `["a" 1]`, `["a" 3]`, and `["a" 4]` in that order. The `[0 ...]` keys describe the separate numeric-key example, not the string-key reproducer. Explicit timestamps must be honored while preserving string keys.
