UnboundLocalError: local variable 'edge_attr' referenced before assignment
### 🐛 Describe the bug

I found that `collect.jinja` template generator will assume the parameter `edge_attr` of the method `message` in the child class of `MessagePassing` to be exist even that parameter is set with a default value and is optional.

I make a minimal example to help reproducing the bug.

```python
import torch
from torch.nn import Linear, Parameter
from torch_geometric.nn import MessagePassing
from torch_geometric.utils import add_self_loops, degree
import numpy as np

class GCNConv(MessagePassing):
    def __init__(self, in_channels, out_channels):
        super().__init__(aggr='add')  # "Add" aggregation (Step 5).
        self.lin = Linear(in_channels, out_channels, bias=False)
        self.bias = Parameter(torch.empty(out_channels))

        self.reset_parameters()

    def reset_parameters(self):
        self.lin.reset_parameters()
        self.bias.data.zero_()

    def forward(self, x, edge_index, edge_attr=None):
        # x has shape [N, in_channels]
        # edge_index has shape [2, E]

        # Step 1: Add self-loops to the adjacency matrix.
        edge_index, _ = add_self_loops(edge_index, num_nodes=x.size(0))

        # Step 2: Linearly transform node feature matrix.
        x = self.lin(x)

        # Step 3: Compute normalization.
        row, col = edge_index
        deg = degree(col, x.size(0), dtype=x.dtype)
        deg_inv_sqrt = deg.pow(-0.5)
        deg_inv_sqrt[deg_inv_sqrt == float('inf')] = 0
        norm = deg_inv_sqrt[row] * deg_inv_sqrt[col]

        # Step 4-5: Start propagating messages.
        out = self.propagate(edge_index, x=x, norm=norm)

        # Step 6: Apply a final bias vector.
        out = out + self.bias

        return out

    def message(self, x_j, norm, edge_attr=None):
        # x_j has shape [E, out_channels]

        # Step 4: Normalize node features.
        return norm.view(-1, 1) * x_j


# Set the number of nodes and edges
num_nodes = 10
num_edges = 20
num_node_features = 5

# Generate random edge indices
edge_index = torch.tensor(np.random.randint(0, num_nodes, size=(2, num_edges)), dtype=torch.long)

# Generate random node features
x = torch.tensor(np.random.randn(num_nodes, num_node_features), dtype=torch.float)
conv = GCNConv(num_node_features, 5)
x = conv(x, edge_index)
```
The code snippet will be terminated with error:
```
Traceback (most recent call last):
  File "/home/ubuntu/testpyg/test.py", line 62, in <module>
    x = conv(x, edge_index)
  File "/home/ubuntu/anaconda3/envs/pyg/lib/python3.10/site-packages/torch/nn/modules/module.py", line 1511, in _wrapped_call_impl
    return self._call_impl(*args, **kwargs)
  File "/home/ubuntu/anaconda3/envs/pyg/lib/python3.10/site-packages/torch/nn/modules/module.py", line 1520, in _call_impl
    return forward_call(*args, **kwargs)
  File "/home/ubuntu/testpyg/test.py", line 37, in forward
    out = self.propagate(edge_index, x=x, norm=norm)
  File "/tmp/__main___GCNConv_propagate_8gx2rr4f.py", line 143, in propagate
    kwargs = self.collect(
  File "/tmp/__main___GCNConv_propagate_8gx2rr4f.py", line 75, in collect
    assert edge_attr is not None
UnboundLocalError: local variable 'edge_attr' referenced before assignment
```


However, if I change the definition of the `message` method to below (removing the optional parameter `edge_attr` with default value None, which should has the same meaning according to Python's semantics since that parameter is not used in the function's body), the code snippet works again:
```python
    def message(self, x_j, norm):
        # x_j has shape [E, out_channels]

        # Step 4: Normalize node features.
        return norm.view(-1, 1) * x_j
```


This issue makes `torch_geometric == 2.5.2` incompatible with [PRODIGY](https://github.com/snap-stanford/prodigy).

### Versions

Collecting environment information...
PyTorch version: 2.2.2
Is debug build: False
CUDA used to build PyTorch: 12.1
ROCM used to build PyTorch: N/A

OS: CentOS Stream 9 (x86_64)
GCC version: (GCC) 11.4.1 20231218 (Red Hat 11.4.1-3)
Clang version: Could not collect
CMake version: Could not collect
Libc version: glibc-2.34

Python version: 3.10.0 (default, Mar  3 2022, 09:58:08) [GCC 7.5.0] (64-bit runtime)
Python platform: Linux-5.14.0-375.el9.x86_64-x86_64-with-glibc2.34
Is CUDA available: False
CUDA runtime version: No CUDA
CUDA_MODULE_LOADING set to: N/A
GPU models and configuration: No CUDA
Nvidia driver version: No CUDA
cuDNN version: No CUDA
HIP runtime version: N/A
MIOpen runtime version: N/A
Is XNNPACK available: True

CPU:
Architecture:                       x86_64
CPU op-mode(s):                     32-bit, 64-bit
Address sizes:                      52 bits physical, 57 bits virtual
Byte Order:                         Little Endian
CPU(s):                             16
On-line CPU(s) list:                0-15
Vendor ID:                          AuthenticAMD
Model name:                         AMD EPYC 9124 16-Core Processor
CPU family:                         25
Model:                              17
Thread(s) per core:                 1
Core(s) per socket:                 16
Socket(s):                          1
Stepping:                           1
Frequency boost:                    enabled
CPU(s) scaling MHz:                 100%
CPU max MHz:                        3711.9141
CPU min MHz:                        1500.0000
BogoMIPS:                           5999.83
Flags:                              fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush mmx fxsr sse sse2 ht syscall nx mmxext fxsr_opt pdpe1gb rdtscp lm constant_tsc rep_good amd_lbr_v2 nopl nonstop_tsc cpuid extd_apicid aperfmperf rapl pni pclmulqdq monitor ssse3 fma cx16 pcid sse4_1 sse4_2 x2apic movbe popcnt aes xsave avx f16c rdrand lahf_lm cmp_legacy svm extapic cr8_legacy abm sse4a misalignsse 3dnowprefetch osvw ibs skinit wdt tce topoext perfctr_core perfctr_nb bpext perfctr_llc mwaitx cpb cat_l3 cdp_l3 invpcid_single hw_pstate ssbd mba perfmon_v2 ibrs ibpb stibp ibrs_enhanced vmmcall fsgsbase bmi1 avx2 smep bmi2 erms invpcid cqm rdt_a avx512f avx512dq rdseed adx smap avx512ifma clflushopt clwb avx512cd sha_ni avx512bw avx512vl xsaveopt xsavec xgetbv1 xsaves cqm_llc cqm_occup_llc cqm_mbm_total cqm_mbm_local avx512_bf16 clzero irperf xsaveerptr rdpru wbnoinvd amd_ppin cppc arat npt lbrv svm_lock nrip_save tsc_scale vmcb_clean flushbyasid decodeassists pausefilter pfthreshold avic v_vmsave_vmload vgif x2avic v_spec_ctrl vnmi avx512vbmi umip pku ospke avx512_vbmi2 gfni vaes vpclmulqdq avx512_vnni avx512_bitalg avx512_vpopcntdq la57 rdpid overflow_recov succor smca fsrm flush_l1d
Virtualization:                     AMD-V
L1d cache:                          512 KiB (16 instances)
L1i cache:                          512 KiB (16 instances)
L2 cache:                           16 MiB (16 instances)
L3 cache:                           64 MiB (4 instances)
NUMA node(s):                       1
NUMA node0 CPU(s):                  0-15
Vulnerability Gather data sampling: Not affected
Vulnerability Itlb multihit:        Not affected
Vulnerability L1tf:                 Not affected
Vulnerability Mds:                  Not affected
Vulnerability Meltdown:             Not affected
Vulnerability Mmio stale data:      Not affected
Vulnerability Retbleed:             Not affected
Vulnerability Spec store bypass:    Mitigation; Speculative Store Bypass disabled via prctl
Vulnerability Spectre v1:           Mitigation; usercopy/swapgs barriers and __user pointer sanitization
Vulnerability Spectre v2:           Mitigation; Enhanced / Automatic IBRS, IBPB conditional, STIBP disabled, RSB filling, PBRSB-eIBRS Not affected
Vulnerability Srbds:                Not affected
Vulnerability Tsx async abort:      Not affected

Versions of relevant libraries:
[pip3] numpy==1.24.3
[pip3] torch==2.2.2
[pip3] torch_geometric==2.5.2
[pip3] torch-scatter==2.1.2
[pip3] torch-sparse==0.6.18
[pip3] torchaudio==2.2.2
[pip3] torchvision==0.17.2
[pip3] triton==2.2.0
[conda] blas                      1.0                         mkl
[conda] libjpeg-turbo             2.0.0                h9bf148f_0    pytorch
[conda] mkl                       2021.4.0           h06a4308_640
[conda] mkl-service               2.4.0           py310h7f8727e_0
[conda] mkl_fft                   1.3.1           py310hd6ae3a3_0
[conda] mkl_random                1.2.2           py310h00e6091_0
[conda] numpy                     1.24.3          py310hd5efca6_0
[conda] numpy-base                1.24.3          py310h8e6c178_0
[conda] pyg                       2.5.2           py310_torch_2.2.0_cu121    pyg
[conda] pytorch                   2.2.2           py3.10_cuda12.1_cudnn8.9.2_0    pytorch
[conda] pytorch-cuda              12.1                 ha16c6d3_5    pytorch
[conda] pytorch-mutex             1.0                        cuda    pytorch
[conda] pytorch-scatter           2.1.2           py310_torch_2.2.0_cu121    pyg
[conda] pytorch-sparse            0.6.18          py310_torch_2.2.0_cu121    pyg
[conda] torchaudio                2.2.2               py310_cu121    pytorch
[conda] torchtriton               2.2.0                     py310    pytorch
[conda] torchvision               0.17.2              py310_cu121    pytorch
