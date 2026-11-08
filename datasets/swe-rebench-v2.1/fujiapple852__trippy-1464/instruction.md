range start index 4 out of range
**Describe the bug**
thread 'tracer-11332' panicked at crates\trippy-core\src\state.rs:636:59:
range start index 4 out of range for slice of length 2
stack backtrace:
   0:     0x7ff7b2badfb3 - <unknown>
   1:     0x7ff7b29e486a - <unknown>
   2:     0x7ff7b2b9d3e7 - <unknown>
   3:     0x7ff7b2baf9a5 - <unknown>
   4:     0x7ff7b2baf7dd - <unknown>
   5:     0x7ff7b2baf4ed - <unknown>
   6:     0x7ff7b2bafbb1 - <unknown>
   7:     0x7ff7b2bafa89 - <unknown>
   8:     0x7ff7b2baf9df - <unknown>
   9:     0x7ff7b2baf9ce - <unknown>
  10:     0x7ff7b2e9b5d1 - <unknown>
  11:     0x7ff7b2e9b53e - <unknown>
  12:     0x7ff7b2c575d8 - <unknown>
  13:     0x7ff7b2c3e6ce - <unknown>
  14:     0x7ff7b2c4bf93 - <unknown>
  15:     0x7ff7b2c5356e - <unknown>
  16:     0x7ff7b2c530d2 - <unknown>
  17:     0x7ff7b2bad54d - <unknown>
  18:     0x7ffaf1ce7034 - BaseThreadInitThunk
  19:     0x7ffaf28a2651 - RtlUserThreadStart
**To Reproduce**

<!-- A description of the steps to reproduce the behavior including the full `trip` or `trip.exe` command line. -->
trip -6 --udp -R dublin  --tui-custom-columns holsravbwdtC -m pretty -C5 -S5000 -P33437 -i20msec -T200msec -f4 -t 5 (some ipv6prefix)::1
Bug +/- stable with same parameters on some ports&ips. But disappears with  (some ipv6prefix)::2 or changing -S or -P.
Key problem parameter(s) -f and -t (slicing)

### Additional contract requirements

When tracing starts at TTL 4 with the maximum TTL set to 5, processing a round containing probes at TTLs 4 and 5 must complete without panicking.
