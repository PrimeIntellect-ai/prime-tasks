Right-justify time output in the console
Currently, it's sometimes a little difficult to compare the benchmark output. It'd be better to right-justify to make it easy to compare across different performance scales. (See sample output below.)

```
name                                                                   time            std                   iterations
-----------------------------------------------------------------------------------------------------------------------
NonBlockingCondition: notify one, no waiters                           49.0 ns         ± 218.03171899854937  1000000
NonBlockingCondition: notify all, no waiters                           48.0 ns         ± 259.1237923013594   1000000
NonBlockingCondition: preWait, cancelWait                              62.0 ns         ± 318.1394131555278   1000000
NonBlockingCondition: preWait, notify, cancelWait                      95.0 ns         ± 383.7078986828835   1000000
NonBlockingCondition: preWait, notify, commitWait                      180.0 ns        ± 530.3777998534739   745911
NonBlockingThreadPool: join, one level                                 688.0 ns        ± 181484.56500114241  7751
NonBlockingThreadPool: join, two levels                                2328.5 ns       ± 362158.9014454464   1294
NonBlockingThreadPool: join, three levels                              4993.0 ns       ± 380630.33014058863  941
NonBlockingThreadPool: join, four levels, three on thread pool thread  5930.5 ns       ± 397880.22706779756  914
NonBlockingThreadPool: parallel for, one level                         4987256.5 ns    ± 958287.8800861727   28
NonBlockingThreadPool: parallel for, two levels                        4492208.0 ns    ± 666873.9680715388   32
AdjacencyList: build a fully-connected graph of size 10                45450.0 ns      ± 11900.774671466019  2643
AdjacencyList: build a fully-connected graph of size 100               4368357.0 ns    ± 332722.03091855097  33
AdjacencyList: build a fully-connected graph of size 1000              432393589.5 ns  ± 5835349.92137541    2
```
