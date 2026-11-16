TypeError: 'list' object is not callable
### 🐛 Describe the bug

```python
from torch.nn import Linear, ReLU, Dropout
from torch_geometric.nn import Sequential, GCNConv, JumpingKnowledge
from torch_geometric.nn import global_mean_pool

model = Sequential('x, edge_index, batch', [
    (Dropout(p=0.5), 'x -> x'),
    (GCNConv(2, 64), 'x, edge_index -> x1'),
    ReLU(inplace=True),
    (GCNConv(64, 64), 'x1, edge_index -> x2'),
    ReLU(inplace=True),
    (lambda x1, x2: [x1, x2], 'x1, x2 -> xs'),
    (JumpingKnowledge("cat", 64, num_layers=2), 'xs -> x'),
    (global_mean_pool, 'x, batch -> x'),
    Linear(2 * 64, 3),
]).to('cpu')
```
It throws `TypeError: 'list' object is not callable`

### Versions

PyTorch version: 2.2.2+cu121
Is debug build: False
CUDA used to build PyTorch: 12.1
ROCM used to build PyTorch: N/A

OS: Ubuntu 22.04.3 LTS (x86_64)
GCC version: (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
Clang version: Could not collect
CMake version: version 3.27.2
Libc version: glibc-2.35

Python version: 3.9.19 | packaged by conda-forge | (main, Mar 20 2024, 12:50:21)  [GCC 12.3.0] (64-bit runtime)
Python platform: Linux-6.2.0-39-generic-x86_64-with-glibc2.35
Is CUDA available: True
CUDA runtime version: 12.4.131
CUDA_MODULE_LOADING set to: LAZY
GPU models and configuration:
GPU 0: NVIDIA GeForce RTX 3090 Ti
GPU 1: NVIDIA GeForce RTX 3090 Ti

Nvidia driver version: 550.54.14
cuDNN version: Probably one of the following:
/usr/lib/x86_64-linux-gnu/libcudnn.so.8.6.0
/usr/lib/x86_64-linux-gnu/libcudnn_adv_infer.so.8.6.0
/usr/lib/x86_64-linux-gnu/libcudnn_adv_train.so.8.6.0
/usr/lib/x86_64-linux-gnu/libcudnn_cnn_infer.so.8.6.0
/usr/lib/x86_64-linux-gnu/libcudnn_cnn_train.so.8.6.0
/usr/lib/x86_64-linux-gnu/libcudnn_ops_infer.so.8.6.0
/usr/lib/x86_64-linux-gnu/libcudnn_ops_train.so.8.6.0
/usr/local/cuda-11.7/targets/x86_64-linux/lib/libcudnn.so.8.5.0
/usr/local/cuda-11.7/targets/x86_64-linux/lib/libcudnn_adv_infer.so.8.5.0
/usr/local/cuda-11.7/targets/x86_64-linux/lib/libcudnn_adv_train.so.8.5.0
/usr/local/cuda-11.7/targets/x86_64-linux/lib/libcudnn_cnn_infer.so.8.5.0
/usr/local/cuda-11.7/targets/x86_64-linux/lib/libcudnn_cnn_train.so.8.5.0
/usr/local/cuda-11.7/targets/x86_64-linux/lib/libcudnn_ops_infer.so.8.5.0
/usr/local/cuda-11.7/targets/x86_64-linux/lib/libcudnn_ops_train.so.8.5.0
HIP runtime version: N/A
MIOpen runtime version: N/A
Is XNNPACK available: True

CPU:
Architecture:                       x86_64
CPU op-mode(s):                     32-bit, 64-bit
Address sizes:                      43 bits physical, 48 bits virtual
Byte Order:                         Little Endian
CPU(s):                             48
On-line CPU(s) list:                0-47
Vendor ID:                          AuthenticAMD
Model name:                         AMD Ryzen Threadripper 3960X 24-Core Processor
CPU family:                         23
Model:                              49
Thread(s) per core:                 2
Core(s) per socket:                 24
Socket(s):                          1
Stepping:                           0
Frequency boost:                    enabled
CPU max MHz:                        3800.0000
CPU min MHz:                        2200.0000
BogoMIPS:                           7585.68
Flags:                              fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good nopl nonstop_tsc cpuid extd_apicid aperfmperf rapl pni pclmulqdq monitor ssse3 fma cx16 sse4_1 sse4_2 movbe popcnt aes xsave avx f16c rdrand lahf_lm cmp_legacy svm extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw ibs skinit wdt tce topoext perfctr_core perfctr_nb bpext perfctr_llc mwaitx cpb cat_l3 cdp_l3 hw_pstate ssbd mba ibpb stibp vmmcall fsgsbase bmi1 avx2 smep bmi2 cqm rdt_a rdseed adx smap clflushopt clwb sha_ni xsaveopt xsavec xgetbv1 cqm_llc cqm_occup_llc cqm_mbm_total cqm_mbm_local clzero irperf xsaveerptr rdpru wbnoinvd amd_ppin arat npt lbrv svm_lock nrip_save tsc_scale vmcb_clean flushbyasid decodeassists pausefilter pfthreshold avic v_vmsave_vmload vgif v_spec_ctrl umip rdpid overflow_recov succor smca sev sev_es
Virtualization:                     AMD-V
L1d cache:                          768 KiB (24 instances)
L1i cache:                          768 KiB (24 instances)
L2 cache:                           12 MiB (24 instances)
L3 cache:                           128 MiB (8 instances)
NUMA node(s):                       1
NUMA node0 CPU(s):                  0-47
Vulnerability Gather data sampling: Not affected
Vulnerability Itlb multihit:        Not affected
Vulnerability L1tf:                 Not affected
Vulnerability Mds:                  Not affected
Vulnerability Meltdown:             Not affected
Vulnerability Mmio stale data:      Not affected
Vulnerability Retbleed:             Mitigation; untrained return thunk; SMT enabled with STIBP protection
Vulnerability Spec rstack overflow: Mitigation; safe RET
Vulnerability Spec store bypass:    Mitigation; Speculative Store Bypass disabled via prctl
Vulnerability Spectre v1:           Mitigation; usercopy/swapgs barriers and __user pointer sanitization
Vulnerability Spectre v2:           Mitigation; Retpolines, IBPB conditional, STIBP always-on, RSB filling, PBRSB-eIBRS Not affected
Vulnerability Srbds:                Not affected
Vulnerability Tsx async abort:      Not affected

Versions of relevant libraries:
[pip3] fast-pytorch-kmeans==0.2.0.1
[pip3] flake8==7.0.0
[pip3] mypy==1.9.0
[pip3] mypy-extensions==1.0.0
[pip3] numpy==1.24.4
[pip3] numpydoc==1.6.0
[pip3] paddle2onnx==1.0.6
[pip3] pytorchts==0.6.0
[pip3] reformer-pytorch==1.4.4
[pip3] torch==2.2.2
[pip3] torch_cluster==1.6.3+pt22cu121
[pip3] torch-ema==0.3
[pip3] torch-geometric==2.6.0
[pip3] torch_scatter==2.1.2+pt22cu121
[pip3] torch_sparse==0.6.18+pt22cu121
[pip3] torch_spline_conv==1.2.2+pt22cu121
[pip3] torchaudio==2.2.2
[pip3] torchmetrics==0.10.1
[pip3] torchsummary==1.5.1
[pip3] torchvision==0.17.2
[pip3] triton==2.2.0
[conda] fast-pytorch-kmeans       0.2.0.1                  pypi_0    pypi
[conda] nomkl                     1.0                  h5ca1d4c_0    conda-forge
[conda] numpy                     1.24.4                   pypi_0    pypi
[conda] numpydoc                  1.6.0              pyhd8ed1ab_0    conda-forge
[conda] pytorchts                 0.6.0                    pypi_0    pypi
[conda] reformer-pytorch          1.4.4                    pypi_0    pypi
[conda] torch                     2.2.2                    pypi_0    pypi
[conda] torch-cluster             1.6.3+pt22cu121          pypi_0    pypi
[conda] torch-ema                 0.3                      pypi_0    pypi
[conda] torch-geometric           2.6.0                    pypi_0    pypi
[conda] torch-scatter             2.1.2+pt22cu121          pypi_0    pypi
[conda] torch-sparse              0.6.18+pt22cu121          pypi_0    pypi
[conda] torch-spline-conv         1.2.2+pt22cu121          pypi_0    pypi
[conda] torchaudio                2.2.2                    pypi_0    pypi
[conda] torchmetrics              0.10.1                   pypi_0    pypi
[conda] torchsummary              1.5.1                    pypi_0    pypi
[conda] torchvision               0.17.2                   pypi_0    pypi
[conda] triton                    2.2.0                    pypi_0    pypi
