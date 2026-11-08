Cat uncoallesced sparse_coo tensor.
### 🐛 Describe the bug

I have a sparse_coo tensor in my dataset. When I want to load this tensor I get an error like this:
```
File "/home/amir/.pyenv/versions/3.9.13/lib/python3.9/site-packages/torch_geometric/data/batch.py", line 97, in from_data_list
    batch, slice_dict, inc_dict = collate(
  File "/home/amir/.pyenv/versions/3.9.13/lib/python3.9/site-packages/torch_geometric/data/collate.py", line 109, in collate
    value, slices, incs = _collate(attr, values, data_list, stores,
  File "/home/amir/.pyenv/versions/3.9.13/lib/python3.9/site-packages/torch_geometric/data/collate.py", line 232, in _collate
    value = cat(values, dim=cat_dim)
  File "/home/amir/.pyenv/versions/3.9.13/lib/python3.9/site-packages/torch_geometric/utils/sparse.py", line 686, in cat
    return cat_coo(tensors, dim)
  File "/home/amir/.pyenv/versions/3.9.13/lib/python3.9/site-packages/torch_geometric/utils/sparse.py", line 509, in cat_coo
    indices.append([HIDDEN])
RuntimeError: Cannot get indices on an uncoalesced tensor, please call .coalesce() first
```
I do not want to coalesce my tensors because I will have some problems with my tensor dimensions.
[HIDDEN]
Can anyone help me with this issue?

### Versions

PyTorch version: N/A
Is debug build: N/A
CUDA used to build PyTorch: N/A
ROCM used to build PyTorch: N/A

OS: Ubuntu 22.04.1 LTS (x86_64)
GCC version: (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
Clang version: Could not collect
CMake version: version 3.22.1
Libc version: glibc-2.35

Python version: 3.9.18 (main, Sep 11 2023, 13:41:44)  [GCC 11.2.0] (64-bit runtime)
Python platform: Linux-5.15.0-92-generic-x86_64-with-glibc2.35
Is CUDA available: N/A
CUDA runtime version: Could not collect
CUDA_MODULE_LOADING set to: N/A
GPU models and configuration:
GPU 0: NVIDIA GeForce RTX 3080
GPU 1: NVIDIA GeForce RTX 3080

Nvidia driver version: 525.147.05
cuDNN version: Could not collect
HIP runtime version: N/A
MIOpen runtime version: N/A
Is XNNPACK available: N/A

CPU:
Architecture:                       x86_64
CPU op-mode(s):                     32-bit, 64-bit
Address sizes:                      39 bits physical, 48 bits virtual
Byte Order:                         Little Endian
CPU(s):                             16
On-line CPU(s) list:                0-15
Vendor ID:                          GenuineIntel
Model name:                         11th Gen Intel(R) Core(TM) i9-11900K @ 3.50GHz
CPU family:                         6
Model:                              167
Thread(s) per core:                 2
Core(s) per socket:                 8
Socket(s):                          1
Stepping:                           1
CPU max MHz:                        5300.0000
CPU min MHz:                        800.0000
BogoMIPS:                           7008.00
Flags:                              fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf tsc_known_freq pni pclmulqdq dtes64 monitor ds_cpl smx est tm2 ssse3 sdbg fma cx16 xtpr pdcm pcid sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm 3dnowprefetch cpuid_fault epb invpcid_single ssbd ibrs ibpb stibp ibrs_enhanced fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid mpx avx512f avx512dq rdseed adx smap avx512ifma clflushopt intel_pt avx512cd sha_ni avx512bw avx512vl xsaveopt xsavec xgetbv1 xsaves dtherm ida arat pln pts hwp hwp_notify hwp_act_window hwp_epp hwp_pkg_req avx512vbmi umip pku ospke avx512_vbmi2 gfni vaes vpclmulqdq avx512_vnni avx512_bitalg avx512_vpopcntdq rdpid fsrm md_clear flush_l1d arch_capabilities
L1d cache:                          384 KiB (8 instances)
L1i cache:                          256 KiB (8 instances)
L2 cache:                           4 MiB (8 instances)
L3 cache:                           16 MiB (1 instance)
NUMA node(s):                       1
NUMA node0 CPU(s):                  0-15
Vulnerability Gather data sampling: Mitigation; Microcode
Vulnerability Itlb multihit:        Not affected
Vulnerability L1tf:                 Not affected
Vulnerability Mds:                  Not affected
Vulnerability Meltdown:             Not affected
Vulnerability Mmio stale data:      Mitigation; Clear CPU buffers; SMT vulnerable
Vulnerability Retbleed:             Mitigation; Enhanced IBRS
Vulnerability Spec rstack overflow: Not affected
Vulnerability Spec store bypass:    Mitigation; Speculative Store Bypass disabled via prctl and seccomp
Vulnerability Spectre v1:           Mitigation; usercopy/swapgs barriers and __user pointer sanitization
Vulnerability Spectre v2:           Mitigation; Enhanced IBRS, IBPB conditional, RSB filling, PBRSB-eIBRS SW sequence
Vulnerability Srbds:                Not affected
Vulnerability Tsx async abort:      Not affected

Versions of relevant libraries:
[pip3] No relevant packages
[conda] No relevant packages

### Additional contract requirements

- DataLoader must be able to batch uncoalesced sparse COO tensors without requiring callers to coalesce them first.
- Concatenating uncoalesced sparse COO tensors must preserve their stored entries rather than merge duplicate coordinates through coalescing.
