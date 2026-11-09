# Proposal for the Meridian High-Performance AI Computing Cluster (MHPACC)

**Pacific Northwest Institute of Technology**
**Meridian AI Research Lab**

**Principal Investigator:** Dr. Evelyn R. Matsuda, Director, Meridian AI Research Lab
**Co-Investigators:** Dr. James K. Okonkwo (Distributed Systems), Dr. Lena Zhao (Scientific ML), Dr. Raj Venkataraman (Computer Vision), Dr. Sarah P. Lindqvist (NLP & LLMs)

**Date of Submission:** November 8, 2025
**Funding Period Requested:** January 2026 -- December 2028 (36 months)
**Total Budget Requested:** $12,500,000

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Research Objectives](#2-research-objectives)
3. [Workload Requirements](#3-workload-requirements)
4. [Proposed Hardware Configuration](#4-proposed-hardware-configuration)
5. [Infrastructure Requirements](#5-infrastructure-requirements)
6. [Budget Breakdown](#6-budget-breakdown)
7. [Timeline](#7-timeline)
8. [Risk Assessment](#8-risk-assessment)
9. [Success Metrics](#9-success-metrics)
10. [Appendices](#10-appendices)

---

## 1. Executive Summary

The Meridian AI Research Lab at the Pacific Northwest Institute of Technology (PNIT) respectfully submits this proposal for the construction and operation of a dedicated high-performance GPU computing cluster --- the Meridian High-Performance AI Computing Cluster (MHPACC). This facility is designed to serve as the primary computational backbone for distributed machine learning training, large-scale inference, and scientific computing workloads across four departments and twelve affiliated research groups.

Over the past five years, the computational demands of the Lab's research portfolio have grown at an annualized rate of approximately 340%. Current infrastructure --- consisting of a shared allocation on the university's general-purpose HPC cluster (Cedar, 24 NVIDIA V100 GPUs) and a small departmental cluster (8 NVIDIA A100 40GB GPUs) --- is no longer sufficient to support the scale, complexity, or timeliness of our research objectives. Researcher queue wait times on the Cedar cluster have averaged 72 hours in the past fiscal year, with peak-period delays exceeding 168 hours. Multiple grant-funded projects have experienced timeline slippage directly attributable to insufficient GPU availability.

The proposed MHPACC cluster will address these constraints by providing a purpose-built facility optimized for three primary workload classes:

- **Large Language Model (LLM) Training:** Pre-training and fine-tuning of models ranging from 7B to 70B parameters for domain-specific scientific applications, requiring sustained multi-node, multi-GPU parallelism with high-bandwidth interconnects.
- **Computer Vision and Medical Imaging:** Training of large vision transformers and real-time segmentation pipelines on high-resolution imaging datasets (up to 4096x4096 pixels per frame), with stringent latency requirements for clinical deployment pathways.
- **Scientific Machine Learning:** Physics-informed neural networks for climate modeling, materials science simulations, and computational fluid dynamics, requiring tight coupling between GPU computation and large-scale data I/O.

We request a total investment of **$12.5 million over 36 months**, encompassing hardware procurement, infrastructure buildout, software ecosystem development, and staffing for ongoing operations and user support. The proposed cluster will serve an immediate user base of 85 researchers (faculty, postdoctoral fellows, and graduate students) across the Departments of Computer Science, Electrical Engineering, Earth & Atmospheric Sciences, and Biomedical Engineering, with planned expansion to partner institutions through a federated access model in Year 2.

This proposal outlines the technical specifications, infrastructure requirements, phased implementation timeline, risk mitigation strategies, and performance metrics that will guide the successful deployment and operation of MHPACC.

---

## 2. Research Objectives

The MHPACC cluster is designed to directly enable five high-priority research programs, each of which has secured or is in active pursuit of external funding. These programs collectively represent $7.2M in current and pending grant support from the National Science Foundation (NSF), the National Institutes of Health (NIH), the Department of Energy (DOE), and the Defense Advanced Research Projects Agency (DARPA).

### 2.1 Training a 70B Parameter Language Model for Scientific Literature Understanding

**Lead PI:** Dr. Sarah P. Lindqvist (NLP & LLMs Group)
**Funding:** NSF Award #2451098 ($1.8M, 2025--2028)

This project aims to develop SciLM-70B, a 70-billion parameter autoregressive language model pre-trained on a curated corpus of 4.2 trillion tokens drawn from scientific publications, patents, technical reports, and structured knowledge bases spanning physics, chemistry, biology, and materials science. The model will be further fine-tuned using reinforcement learning from human feedback (RLHF) with domain expert annotations for tasks including literature synthesis, hypothesis generation, and automated methods section drafting.

Current pre-training of a 7B parameter pilot model on our existing 8-GPU A100 cluster required 45 days of continuous computation. Scaling to 70B parameters on the same hardware is estimated to require approximately 18 months --- well beyond acceptable project timelines. The proposed MHPACC cluster, using 3D parallelism (data, tensor, and pipeline parallelism) across 64 H100 GPUs, would reduce this to an estimated 21 days.

### 2.2 Distributed Reinforcement Learning for Robotic Manipulation

**Lead PI:** Dr. James K. Okonkwo (Distributed Systems Group)
**Funding:** DARPA Award HR0011-25-2-0034 ($2.1M, 2025--2027)

This research program investigates massively parallel reinforcement learning (RL) for dexterous robotic manipulation in unstructured environments. The approach leverages the IsaacGym physics simulator to run 16,384 parallel simulation environments on GPU, with policy training using Proximal Policy Optimization (PPO) and Soft Actor-Critic (SAC) algorithms.

The computational bottleneck lies in the requirement for millions of environment steps per policy update, with each environment requiring GPU-accelerated physics simulation at 240 Hz. Current infrastructure limits us to 2,048 parallel environments, resulting in policy convergence times of 3--5 days for moderately complex tasks. The proposed cluster would enable scaling to the full 16,384 environments, reducing convergence to approximately 8--12 hours and enabling rapid iteration across the project's 24 planned task configurations.

### 2.3 Climate Modeling with Physics-Informed Neural Networks

**Lead PI:** Dr. Lena Zhao (Scientific ML Group)
**Funding:** DOE Award DE-SC0024178 ($1.6M, 2025--2028)

This project develops hybrid neural network--numerical solver architectures for regional climate downscaling at 1 km resolution. The approach embeds the governing partial differential equations of atmospheric dynamics (Navier-Stokes equations, radiative transfer, moisture transport) as soft constraints in the neural network loss function, enforcing physical consistency while learning sub-grid-scale parameterizations from high-resolution simulation data.

Training data comprises 850 TB of ERA5 reanalysis data, CMIP6 model outputs, and proprietary mesoscale simulation datasets. The training pipeline requires loading 128 GB data batches into GPU memory at each optimization step, with gradient computation spanning approximately 3.2 TFLOPS per batch. On current hardware, a single training run for a regional model (Pacific Northwest, 500 km x 500 km domain) requires 14 days. The proposed cluster would reduce this to 36 hours, enabling the team to conduct the systematic hyperparameter sweeps and ablation studies necessary for publication-quality results.

### 2.4 Federated Learning Across Partner Institutions

**Lead PI:** Dr. Evelyn R. Matsuda (Meridian AI Research Lab)
**Funding:** NSF Award #2510234 ($1.2M, pending review, expected notification March 2026)

This initiative establishes a federated learning testbed connecting PNIT with four partner universities (University of Oregon, Oregon State University, University of Washington, and University of British Columbia) for privacy-preserving collaborative model training on sensitive datasets. Applications include clinical genomics, campus network intrusion detection, and regional economic forecasting.

The MHPACC cluster would serve as the primary aggregation server and also provide each partner institution with a sandboxed virtual partition for local model training. The federated protocol requires the central server to aggregate model updates from up to 50 participating nodes within a 60-second window to maintain training synchrony, necessitating both high-bandwidth networking and dedicated GPU resources for secure aggregation (using homomorphic encryption, which is computationally intensive).

### 2.5 Real-Time Medical Image Segmentation Pipeline

**Lead PI:** Dr. Raj Venkataraman (Computer Vision Group)
**Funding:** NIH R01 Award 5R01-CA-267891 ($1.5M, 2024--2027)

This project develops a real-time 3D segmentation pipeline for intraoperative MRI-guided neurosurgery. The system must segment brain tumor boundaries in volumetric MRI scans (256 x 256 x 192 voxels, 1mm isotropic resolution) within 500 milliseconds to support surgical navigation. The training pipeline involves a cascade of three specialized U-Net architectures (coarse localization, fine segmentation, boundary refinement) trained on a multi-institutional dataset of 12,000 annotated brain MRI volumes.

Training the full cascade on current hardware requires 28 days per experimental configuration. The proposed cluster would reduce this to approximately 3 days, critically enabling the team to meet FDA regulatory submission timelines (Q4 2027) that require documented evidence of systematic model validation across multiple architectural variants and training configurations.

---

## 3. Workload Requirements

The following table summarizes the computational requirements for each research program. All estimates are based on profiling of current workloads and published benchmarks for comparable model architectures.

### 3.1 Summary of Computational Requirements

| Project | Est. FLOPS per Training Run | Memory per Node | Current Hardware Duration | Proposed Duration | Data Throughput | Storage Needs |
|---|---|---|---|---|---|---|
| SciLM-70B | 1.2 x 10^24 FLOP | 640 GB (8x 80GB GPUs) | ~18 months (est.) | ~21 days | 12 GB/s sustained | 180 TB |
| Robotic RL | 8.5 x 10^20 FLOP per policy | 320 GB (8x 40GB active) | 3--5 days | 8--12 hours | 4 GB/s burst | 25 TB |
| Climate PINNs | 4.7 x 10^22 FLOP | 640 GB (8x 80GB GPUs) | 14 days | 36 hours | 18 GB/s sustained | 850 TB (raw) + 120 TB (processed) |
| Federated Learning | 2.1 x 10^21 FLOP (aggregate) | 160 GB (aggregation node) | N/A (new project) | Continuous | 2 GB/s (network-bound) | 45 TB |
| Medical Segmentation | 3.8 x 10^21 FLOP | 480 GB (8x 80GB GPUs, mixed) | 28 days | 3 days | 8 GB/s sustained | 65 TB |

### 3.2 Detailed Workload Profiles

#### 3.2.1 SciLM-70B Language Model Training

- **Model Architecture:** 70B parameter decoder-only transformer, 80 layers, hidden dimension 8192, 64 attention heads, GQA with 8 KV heads, RoPE positional encoding, SwiGLU activation
- **Training Tokens:** 4.2 trillion tokens, sequence length 4096
- **Parallelism Strategy:** 3D parallelism --- tensor parallelism (degree 8, intra-node), pipeline parallelism (degree 8, inter-node), data parallelism (degree 1--8, scaling)
- **Per-GPU Memory Breakdown:**
  - Model parameters (FP16): ~35 GB per pipeline stage (8-way split)
  - Optimizer states (FP32, AdamW): ~35 GB per pipeline stage
  - Activations (with selective recomputation): ~8 GB
  - Communication buffers: ~2 GB
  - **Total per GPU:** ~80 GB (requires 80 GB HBM3)
- **Compute Requirements:** 6 x model_params x num_tokens = 6 x 70 x 10^9 x 4.2 x 10^12 = 1.76 x 10^24 FLOP (forward + backward)
- **Target MFU (Model FLOPS Utilization):** 42--48% (based on published H100 benchmarks for similar-scale models)
- **Inter-Node Communication:** All-reduce operations for data-parallel gradient synchronization require approximately 280 GB of data transfer per optimization step, necessitating InfiniBand HDR (400 Gbps) to avoid communication bottlenecks
- **I/O Requirements:** Tokenized training data streamed from Lustre filesystem at 12 GB/s aggregate across all data-parallel ranks

#### 3.2.2 Distributed Reinforcement Learning

- **Simulation:** IsaacGym with 16,384 parallel environments, each running at 240 Hz simulation frequency
- **Policy Network:** Transformer-based policy with 850M parameters, processing proprioceptive and visual observations (128x128 RGB-D)
- **GPU Allocation:** 4 GPUs for simulation (2,048 environments per GPU x 2 simulation workers), 4 GPUs for policy training and inference
- **Memory Requirements per Simulation GPU:**
  - Environment state buffers: ~24 GB
  - Rendering buffers: ~16 GB
  - Physics engine overhead: ~8 GB
  - **Total:** ~48 GB per simulation GPU
- **Rollout Buffer:** 256 steps x 16,384 environments x 1.2 KB per transition = ~5 GB per rollout (stored in GPU memory)
- **Training Throughput:** Target 500M environment steps per hour
- **Communication Pattern:** Asynchronous rollout collection with synchronous policy updates; low inter-node bandwidth requirements

#### 3.2.3 Climate Physics-Informed Neural Networks

- **Model Architecture:** Modified FourCastNet with physics-informed loss terms, 2.1B parameters
- **Input Resolution:** 0.25-degree global grid (721 x 1440 grid points, 13 pressure levels, 7 prognostic variables) downscaled to 1 km regional grid
- **Training Data Pipeline:**
  - Raw ERA5 data (0.25-degree, hourly, 1979--2024): 650 TB on tape archive
  - Pre-processed training tensors (regional subsets, normalized): 120 TB on Lustre
  - Batch size: 64 regional patches (256 x 256 grid, 13 levels, 7 variables, 24 timesteps)
  - Per-batch memory: ~18 GB
- **Compute Profile:** Dominated by PDE residual evaluation in loss function, requiring automatic differentiation through 4th-order spatial finite differences on the neural network output; approximately 3.2x overhead compared to standard MSE loss
- **Multi-GPU Strategy:** Data parallelism with gradient accumulation; each GPU processes 8 patches per micro-batch
- **I/O Bottleneck:** Sustained 18 GB/s read throughput from parallel filesystem; data loading is currently the primary bottleneck on existing hardware

#### 3.2.4 Federated Learning Aggregation

- **Protocol:** Federated Averaging (FedAvg) with secure aggregation using partial homomorphic encryption (Paillier scheme, 2048-bit keys)
- **Model Sizes:** Varies by application; largest model is a 1.3B parameter genomics transformer
- **Aggregation Compute:** Decryption and weighted averaging of model updates from 50 clients; Paillier decryption at 2048-bit requires approximately 0.5 ms per parameter, yielding ~650 GPU-seconds for the 1.3B model per aggregation round
- **Aggregation Frequency:** Every 60 seconds for time-critical applications (intrusion detection), every 300 seconds for genomics
- **Dedicated Resources:** 2 GPUs for encryption/decryption (CUDA-accelerated Paillier), 1 GPU for aggregated model validation, 1 GPU for anomaly detection on model updates (Byzantine fault tolerance)
- **Network Requirements:** 10 Gbps external connectivity to partner institutions; 100 Gbps internal connectivity to Lustre for checkpoint storage

#### 3.2.5 Medical Image Segmentation

- **Model Architecture:** Cascaded 3D U-Net (3 stages): localization net (28M params), segmentation net (145M params), refinement net (92M params)
- **Training Data:** 12,000 annotated 3D MRI volumes (256 x 256 x 192, float32), approximately 65 TB including augmented variants
- **Per-GPU Memory:**
  - Single 3D volume (float32): 48 MB
  - Batch of 8 volumes with augmentation: ~1.5 GB
  - Largest model (segmentation net) with gradients and optimizer: ~12 GB
  - Activation memory (no checkpointing): ~35 GB
  - **Total:** ~50 GB per GPU
- **Training Configuration:** 6 GPUs for training (2 per cascade stage), 2 GPUs for continuous validation and hyperparameter search (Optuna)
- **Mixed Precision:** TF32 for compute, FP32 for accumulation; approximately 1.8x speedup over pure FP32
- **Inference Latency Target:** < 500 ms for full cascade on single volume; requires model optimization (TensorRT) and dedicated inference GPU

---

## 4. Proposed Hardware Configuration

We present three hardware configuration options, each designed to meet the workload requirements outlined in Section 3 with different cost-performance tradeoffs. Our recommendation, based on the analysis below, is **Option A** for maximum capability, or **Option C** for an optimized cost-performance balance.

### 4.1 Option A: 64x NVIDIA H100 SXM (Recommended for Maximum Performance)

**Configuration:**

| Component | Specification | Quantity |
|---|---|---|
| GPU Nodes | 8x NVIDIA H100 SXM 80GB per node, NVLink 4.0 (900 GB/s bisection BW) | 8 nodes |
| Total GPUs | NVIDIA H100 SXM 80GB HBM3 | 64 |
| CPU per Node | 2x Intel Xeon Platinum 8480+ (56 cores each) | 16 CPUs |
| System Memory | 2 TB DDR5-4800 ECC per node | 16 TB total |
| Local NVMe | 4x 7.68 TB NVMe U.2 per node (30.7 TB per node) | 245.8 TB total |
| Interconnect (Intra-node) | NVLink 4.0, 900 GB/s GPU-to-GPU | Included |
| Interconnect (Inter-node) | NVIDIA ConnectX-7 400 Gbps InfiniBand NDR | 2 per node |
| Node Platform | NVIDIA DGX H100 or equivalent (e.g., Supermicro AS-8125GS-TNHR) | 8 |

**Performance Estimates:**

- Peak FP16 Tensor Core performance: 64 x 1,979 TFLOPS = 126.7 PFLOPS (peak)
- Estimated sustained performance (42% MFU for LLM training): ~53.2 PFLOPS
- SciLM-70B estimated training time: **18--21 days**
- All-reduce bandwidth (ring, 8 nodes): ~350 GB/s effective

**Power and Cooling:**

- Per-node TDP (GPU + CPU + system): ~10.2 kW
- Total GPU node power: 81.6 kW
- Storage, networking, and management nodes: ~18 kW
- Cooling overhead (PUE 1.15 with direct liquid cooling): ~15 kW
- **Total facility power draw: ~115 kW (Option A only), ~350 kW including full infrastructure**

**Estimated Cost:**

| Item | Unit Cost | Quantity | Total |
|---|---|---|---|
| DGX H100 Node (or equivalent) | $320,000 | 8 | $2,560,000 |
| NVIDIA H100 SXM GPUs (if bare-metal build) | $33,000 | 64 | $2,112,000 |
| InfiniBand NDR switches (Quantum-2 QM9700) | $28,000 | 4 | $112,000 |
| InfiniBand cables and adapters | -- | -- | $45,000 |
| CPU, memory, NVMe (per node) | $65,000 | 8 | $520,000 |
| **Subtotal (Option A - DGX path)** | | | **$3,237,000** |
| **Subtotal (Option A - bare-metal build)** | | | **$2,789,000** |

*Note: Costs reflect Q3 2025 pricing and are subject to change. DGX path includes vendor support and optimized firmware; bare-metal build requires additional system integration effort.*

### 4.2 Option B: 128x NVIDIA A100 80GB

**Configuration:**

| Component | Specification | Quantity |
|---|---|---|
| GPU Nodes | 8x NVIDIA A100 80GB SXM per node, NVLink 3.0 (600 GB/s) | 16 nodes |
| Total GPUs | NVIDIA A100 80GB SXM HBM2e | 128 |
| CPU per Node | 2x AMD EPYC 9454 (48 cores each) | 32 CPUs |
| System Memory | 1 TB DDR5-4800 ECC per node | 16 TB total |
| Local NVMe | 4x 3.84 TB NVMe U.2 per node | 245.8 TB total |
| Interconnect (Intra-node) | NVLink 3.0, 600 GB/s GPU-to-GPU | Included |
| Interconnect (Inter-node) | NVIDIA ConnectX-6 200 Gbps InfiniBand HDR | 2 per node |
| Node Platform | NVIDIA DGX A100 or equivalent | 16 |

**Performance Estimates:**

- Peak FP16 Tensor Core performance: 128 x 312 TFLOPS = 39.9 PFLOPS (peak)
- Estimated sustained performance (38% MFU): ~15.2 PFLOPS
- SciLM-70B estimated training time: **58--65 days**
- All-reduce bandwidth (ring, 16 nodes): ~175 GB/s effective

**Power and Cooling:**

- Per-node TDP: ~6.5 kW
- Total GPU node power: 104 kW
- Total facility power draw: ~380 kW (higher node count increases overhead)

**Estimated Cost:**

| Item | Unit Cost | Quantity | Total |
|---|---|---|---|
| DGX A100 Node (or equivalent) | $175,000 | 16 | $2,800,000 |
| InfiniBand HDR switches | $18,000 | 6 | $108,000 |
| InfiniBand cables and adapters | -- | -- | $62,000 |
| **Subtotal (Option B)** | | | **$2,970,000** |

*Note: A100 systems are more readily available and carry lower per-unit costs, but the aggregate training time for flagship workloads (SciLM-70B) is approximately 3x longer than Option A.*

### 4.3 Option C: Hybrid -- 32x H100 + 64x A100 (Recommended for Cost Optimization)

**Configuration:**

| Component | Specification | Quantity |
|---|---|---|
| H100 GPU Nodes | 8x NVIDIA H100 SXM 80GB per node | 4 nodes (32 GPUs) |
| A100 GPU Nodes | 8x NVIDIA A100 80GB SXM per node | 8 nodes (64 GPUs) |
| Total GPUs | 32x H100 + 64x A100 | 96 |
| Interconnect | InfiniBand NDR 400 Gbps (H100 nodes), HDR 200 Gbps (A100 nodes) | Mixed fabric |

**Rationale:** The hybrid configuration allocates H100 nodes to the most compute-intensive workloads (SciLM-70B training, climate PINN training) while using A100 nodes for workloads that are less sensitive to per-GPU throughput (robotic RL simulation, federated learning aggregation, medical image segmentation, and general-purpose research jobs).

**Performance Estimates:**

- Combined peak FP16: (32 x 1,979) + (64 x 312) = 63.3 + 20.0 = 83.3 PFLOPS
- SciLM-70B on H100 partition (32 GPUs): **38--42 days**
- Climate PINNs on H100 partition: **~18 hours** (improved over current 14 days)
- Robotic RL on A100 partition: **10--14 hours**
- Medical segmentation on A100 partition: **4--5 days**

**Estimated Cost:**

| Item | Unit Cost | Quantity | Total |
|---|---|---|---|
| H100 nodes (DGX or equivalent) | $320,000 | 4 | $1,280,000 |
| A100 nodes (DGX or equivalent) | $175,000 | 8 | $1,400,000 |
| InfiniBand switches (mixed fabric) | -- | -- | $168,000 |
| Cabling and adapters | -- | -- | $55,000 |
| **Subtotal (Option C)** | | | **$2,903,000** |

### 4.4 Configuration Comparison Summary

| Metric | Option A (64x H100) | Option B (128x A100) | Option C (Hybrid) |
|---|---|---|---|
| Peak PFLOPS (FP16) | 126.7 | 39.9 | 83.3 |
| SciLM-70B Training Time | 18--21 days | 58--65 days | 38--42 days |
| Total GPU Count | 64 | 128 | 96 |
| Hardware Cost | $2.8--3.2M | $3.0M | $2.9M |
| Power Draw | ~350 kW | ~380 kW | ~365 kW |
| Node Count | 8 | 16 | 12 |
| Management Complexity | Low | Moderate | Moderate-High |

**Recommendation:** We recommend **Option A** as the primary configuration if the budget permits prioritization of maximum per-GPU performance and operational simplicity. The H100's 3.2x improvement in FP16 throughput over the A100, combined with NVLink 4.0's higher bisection bandwidth, delivers substantially faster time-to-result for the flagship SciLM-70B project. If budget flexibility is required, **Option C** provides a pragmatic compromise, enabling the LLM workload on the H100 partition while supporting all other workloads on the A100 partition at competitive performance levels.

---

## 5. Infrastructure Requirements

### 5.1 Network Infrastructure

#### 5.1.1 High-Performance Interconnect (GPU Cluster Fabric)

- **Technology:** NVIDIA Quantum-2 InfiniBand NDR (400 Gbps per port)
- **Topology:** Fat-tree with 2:1 oversubscription at the spine layer
- **Switches:** 4x NVIDIA QM9700 (64-port NDR switches) for leaf layer; 2x QM9700 for spine layer
- **Per-Node Connectivity:** 2x 400 Gbps NDR ports (dual-rail for redundancy and bandwidth aggregation, yielding 800 Gbps per node)
- **Aggregate Bisection Bandwidth:** 3.2 Tbps (sufficient for all-reduce operations across 8 H100 nodes without significant communication bottleneck)
- **Latency:** < 1.0 microsecond port-to-port (critical for synchronous distributed training)

#### 5.1.2 Management and Storage Network

- **Technology:** 100 Gbps Ethernet (Arista 7280R3 or equivalent)
- **Connectivity:** Dual 100 GbE per compute node (for Lustre client traffic and management)
- **Storage Network Bandwidth:** 1.6 Tbps aggregate to Lustre filesystem (8 nodes x 200 Gbps)

#### 5.1.3 External Connectivity

- **Campus Backbone:** 2x 100 Gbps uplinks to PNIT campus network
- **Research Network:** Direct peering with Internet2 via Pacific Northwest Gigapop (100 Gbps) for data transfer to partner institutions and national facilities
- **Federated Learning Network:** Dedicated 10 Gbps VLAN with WireGuard tunnels to four partner institutions

### 5.2 Storage Infrastructure

#### 5.2.1 Parallel Filesystem (Primary Working Storage)

- **Technology:** Lustre 2.15 parallel filesystem
- **Capacity:** 2 PB usable (raw capacity approximately 2.7 PB with RAID6 protection)
- **Configuration:**
  - 2x Metadata Servers (MDS) with Intel Xeon Platinum 8480+, 512 GB RAM, NVMe-based MDT
  - 12x Object Storage Servers (OSS) with 2x 200 Gbps Ethernet each
  - 96x 20 TB NL-SAS drives (distributed across 12 OSS, RAID6 with 8+2 configuration)
  - 12x 3.84 TB NVMe SSDs for Lustre Progressive File Layout (PFL) fast tier
- **Performance Targets:**
  - Sequential read: 120 GB/s aggregate
  - Sequential write: 80 GB/s aggregate
  - Metadata operations: > 100,000 ops/sec
- **File System Policies:** Lustre PFL configured to place small files (< 1 MB) on NVMe tier; large files striped across 8 OSTs with 4 MB stripe size

#### 5.2.2 Archival and Backup Storage

- **Technology:** IBM Spectrum Scale (GPFS) with tape backend
- **Capacity:** 10 PB tape archive (LTO-9)
- **Purpose:** Long-term storage of raw datasets, model checkpoints, and training logs
- **Data Management Policy:** Active data on Lustre with 90-day inactivity migration to tape; policy engine (Robinhood) for automated lifecycle management

#### 5.2.3 Local Node Storage

- **Per-Node NVMe:** 4x 7.68 TB NVMe (30.7 TB per node, 245.8 TB total across 8 nodes)
- **Purpose:** Scratch space for intermediate computation, checkpoint staging, and data loader prefetch buffers
- **Filesystem:** ext4 with LVM, or XFS, configured as /scratch (ephemeral, not backed up)

### 5.3 Power Infrastructure

#### 5.3.1 Power Requirements

| Component | Estimated Power (kW) |
|---|---|
| GPU compute nodes (8x H100 nodes) | 81.6 |
| Storage servers (12 OSS + 2 MDS) | 28.0 |
| Network switches and infrastructure | 8.5 |
| Management nodes (2x login, 1x scheduler, 1x monitoring) | 6.0 |
| Cooling systems (direct liquid cooling loops, CDUs) | 45.0 |
| UPS overhead and power distribution losses (8%) | 27.0 |
| **Total Estimated Power** | **~365 kW** |

*Note: Actual power draw will vary between 300 kW (idle/low utilization) and 500 kW (sustained full-load burst with all GPUs at TDP) depending on workload characteristics.*

#### 5.3.2 Power Distribution

- **Utility Feed:** Dedicated 500 kVA transformer from campus 12.47 kV distribution
- **UPS:** 2x 250 kVA online double-conversion UPS (N+1 redundancy) with 15-minute battery runtime
- **PDUs:** Intelligent rack PDUs with per-outlet metering and remote management (ServerTech or Raritan)
- **Generator Backup:** Connection to campus emergency generator (shared resource, 2 MW capacity)

### 5.4 Cooling Infrastructure

#### 5.4.1 Direct Liquid Cooling (DLC)

Given the power density of the H100 GPU nodes (~10 kW per node in a 2U--4U form factor, yielding rack-level power densities of 40--80 kW per rack), conventional air cooling is insufficient. The proposed cooling solution is:

- **Primary Cooling:** Rear-door heat exchangers (RDHx) with chilled water loop for GPU nodes
- **GPU-Level Cooling:** Direct-to-chip liquid cooling plates (cold plates) for H100 GPUs and CPUs, with manifold distribution within each node
- **Coolant Distribution Units (CDUs):** 4x in-row CDUs, each rated for 100 kW cooling capacity, connected to the building chilled water loop (7/12 degree C supply/return)
- **Secondary Cooling:** Precision air conditioning (2x 30 kW CRAC units) for storage and network equipment
- **Monitoring:** Per-node coolant flow sensors and temperature probes integrated into the cluster management system (Redfish/IPMI)

#### 5.4.2 Environmental Requirements

- **Operating Temperature:** 18--27 degrees C (ASHRAE A1 class)
- **Humidity:** 20--80% relative humidity, non-condensing
- **Chilled Water Supply:** 100 GPM at 7 degrees C, dedicated branch from campus chilled water plant

### 5.5 Physical Space

- **Minimum Floor Space:** 200 sq ft (approximately 19 sq m) dedicated data center space
- **Recommended Floor Space:** 350 sq ft (approximately 32 sq m) to accommodate future expansion, staging area, and maintenance access
- **Floor Loading:** Minimum 250 lbs/sq ft (raised floor or slab)
- **Rack Count:** 6--8 standard 42U racks (4 for compute, 2 for storage, 1 for networking, 1 for management/staging)
- **Cable Management:** Overhead cable trays for power and fiber; under-floor or overhead for chilled water piping
- **Physical Security:** Card access control, CCTV monitoring, environmental sensors (temperature, humidity, water leak detection)

**Proposed Location:** Room B-142, Meridian Engineering Building basement. This space is adjacent to the campus chilled water plant and has existing 480V three-phase power distribution. A site survey conducted in September 2025 confirmed that the space meets structural, electrical, and plumbing prerequisites with minor modifications (installation of supplemental PDUs and chilled water branch piping).

---

## 6. Budget Breakdown

The total requested budget of **$12,500,000** over 36 months is allocated across five major categories as detailed below. All costs are in US dollars and reflect Q3 2025 market pricing with a 5% inflation adjustment applied to Year 2 and Year 3 expenditures.

### 6.1 High-Level Budget Summary

| Category | Amount | % of Total |
|---|---|---|
| Hardware (Compute, Storage, Networking) | $8,500,000 | 68.0% |
| Infrastructure (Facilities, Power, Cooling) | $1,500,000 | 12.0% |
| Software Licenses and Tools | $500,000 | 4.0% |
| Personnel (36 months) | $1,500,000 | 12.0% |
| Contingency Reserve | $500,000 | 4.0% |
| **Total** | **$12,500,000** | **100%** |

### 6.2 Detailed Budget

#### 6.2.1 Hardware -- $8,500,000

| Item | Description | Cost |
|---|---|---|
| GPU Compute Nodes | 8x DGX H100 (or equivalent, 64 GPUs total) | $2,560,000 |
| Additional GPU Memory/NVMe Upgrades | Per-node NVMe expansion, memory upgrades | $320,000 |
| InfiniBand Network Fabric | QM9700 switches, cables, adapters (NDR 400 Gbps) | $380,000 |
| Lustre Parallel Filesystem | 2 PB usable: 12 OSS, 2 MDS, 96 NL-SAS + 12 NVMe | $1,850,000 |
| Archival Storage | LTO-9 tape library, 10 PB capacity, 2 tape drives | $420,000 |
| Ethernet Network Infrastructure | 100 GbE switches, cabling, management network | $185,000 |
| Management and Login Nodes | 2x login nodes, 1x scheduler node, 1x monitoring | $240,000 |
| UPS Systems | 2x 250 kVA online UPS with battery cabinets | $380,000 |
| Racks, PDUs, Cable Management | 8x 42U racks, intelligent PDUs, cable trays | $165,000 |
| Spare Parts and Warranty Extensions | 3-year extended warranty, critical spares pool | $520,000 |
| Shipping, Installation, Vendor Services | Delivery, physical installation, vendor commissioning | $480,000 |
| **Hardware Subtotal** | | **$7,500,000** |
| **Year 2--3 Hardware Refresh/Expansion** | Additional storage, replacement parts, minor upgrades | **$1,000,000** |
| **Hardware Total** | | **$8,500,000** |

#### 6.2.2 Infrastructure -- $1,500,000

| Item | Description | Cost |
|---|---|---|
| Electrical Upgrades | 500 kVA transformer, panel upgrades, conduit runs | $420,000 |
| Cooling System Installation | 4x CDUs, cold plate manifolds, piping, RDHx units | $385,000 |
| Chilled Water Branch Piping | Connection to campus chilled water plant, valves, controls | $145,000 |
| Room Preparation | Raised floor reinforcement, fire suppression (FM-200), environmental monitoring | $210,000 |
| Physical Security | Card access, CCTV, leak detection sensors | $65,000 |
| Generator Connection | Tie-in to campus emergency generator, ATS installation | $125,000 |
| Fiber Optic Runs | Campus backbone connectivity, inter-building fiber | $85,000 |
| Commissioning and Testing | Third-party commissioning agent, thermal/electrical testing | $65,000 |
| **Infrastructure Total** | | **$1,500,000** |

#### 6.2.3 Software Licenses and Tools -- $500,000

| Item | Description | Annual Cost | 3-Year Total |
|---|---|---|---|
| NVIDIA AI Enterprise License | NGC containers, RAPIDS, TensorRT, Triton | $55,000 | $165,000 |
| Slurm Workload Manager (SchedMD) | Enterprise support license | $12,000 | $36,000 |
| Bright Cluster Manager (or equivalent) | Cluster provisioning and monitoring | $18,000 | $54,000 |
| JupyterHub Enterprise | Multi-user notebook environment | $8,000 | $24,000 |
| Weights & Biases (Enterprise) | Experiment tracking and model registry | $15,000 | $45,000 |
| MLflow + Kubeflow Licenses | MLOps pipeline orchestration | $10,000 | $30,000 |
| Security and Compliance Tools | Vulnerability scanning, audit logging | $12,000 | $36,000 |
| Lustre Support (DDN or Whamcloud) | Filesystem vendor support contract | $25,000 | $75,000 |
| Miscellaneous (version control, CI/CD) | GitLab EE, container registry, misc. tools | $11,667 | $35,000 |
| **Software Total** | | | **$500,000** |

#### 6.2.4 Personnel -- $1,500,000

| Position | FTE | Annual Salary + Benefits | 3-Year Total |
|---|---|---|---|
| Senior Systems Administrator (HPC) | 1.0 | $145,000 | $435,000 |
| Systems Administrator (Storage/Network) | 1.0 | $125,000 | $375,000 |
| ML Infrastructure Engineer | 1.0 | $155,000 | $465,000 |
| Student Assistants (part-time, user support) | 0.5 | $25,000 | $75,000 |
| Training and Professional Development | -- | $50,000 | $150,000 |
| **Personnel Total** | | | **$1,500,000** |

*Note: Salary figures include a 30% fringe benefit rate and are benchmarked against Pacific Northwest regional market rates for HPC professionals.*

#### 6.2.5 Contingency Reserve -- $500,000

The contingency reserve (4% of total budget) is allocated to address unforeseen costs including:

- GPU price fluctuations and supply chain surcharges
- Scope changes in infrastructure buildout (e.g., additional electrical capacity)
- Emergency hardware replacements outside warranty coverage
- Consultant fees for specialized engineering challenges

Contingency funds will be managed by the PI with approval from the PNIT Office of Research Administration. Unspent contingency funds in Years 1--2 will roll forward; any remaining balance at project conclusion will be returned to the funding source.

---

## 7. Timeline

The MHPACC project will be executed in four phases over 36 months, with key milestones and decision gates at each phase boundary.

### 7.1 Phase 1: Procurement and Site Preparation (Months 1--4)

| Month | Activity | Responsible Party | Deliverable |
|---|---|---|---|
| 1 | Finalize hardware specifications and vendor selection; issue RFP | PI, Procurement Office | Signed vendor contracts |
| 1--2 | Engage facilities engineering firm for site assessment and design | Facilities Management | Architectural and MEP drawings |
| 2--3 | Begin electrical and cooling infrastructure installation | Facilities contractor | Transformer installation, conduit runs |
| 2--3 | Procure networking equipment (InfiniBand switches, Ethernet) | PI, Systems team | Equipment received and inventoried |
| 3--4 | Complete room preparation (raised floor, fire suppression, security) | Facilities contractor | Room ready for equipment |
| 3--4 | Receive and inventory GPU compute nodes and storage equipment | Systems team | All hardware on-site |
| 4 | **Phase 1 Gate Review:** Site ready, all hardware received | PI, Facilities, IT governance | Go/no-go for Phase 2 |

### 7.2 Phase 2: Installation and Configuration (Months 5--8)

| Month | Activity | Responsible Party | Deliverable |
|---|---|---|---|
| 5 | Physical rack installation, power distribution, cooling connections | Systems team, vendor engineers | All nodes racked and powered |
| 5--6 | InfiniBand fabric installation and link validation | Systems team, network vendor | Full-bisection fabric verified |
| 6 | Lustre filesystem deployment, performance benchmarking | Storage admin, Lustre vendor | 2 PB filesystem online, IOR benchmarks met |
| 6--7 | Operating system provisioning (Rocky Linux 9), driver installation | Systems team | All nodes booted, NVIDIA drivers verified |
| 7 | Slurm cluster configuration, user account provisioning | Systems team, ML engineer | Slurm scheduling operational |
| 7--8 | Software stack deployment (CUDA 12.x, PyTorch, containers) | ML engineer | NGC containers tested, JupyterHub live |
| 8 | Security hardening, vulnerability assessment | IT Security team | Compliance audit passed |
| 8 | **Phase 2 Gate Review:** Cluster operational, baseline benchmarks complete | PI, Systems team, IT governance | Go/no-go for Phase 3 |

### 7.3 Phase 3: Testing and Pilot Workloads (Months 9--12)

| Month | Activity | Responsible Party | Deliverable |
|---|---|---|---|
| 9 | NCCL benchmark suite (all-reduce, all-gather, point-to-point) | ML engineer | Communication performance validated |
| 9--10 | MLPerf Training benchmark execution | ML engineer, PI | Published MLPerf results |
| 10 | Pilot workload: SciLM-7B (small-scale LLM training) | Dr. Lindqvist's group | Successful multi-node training run |
| 10--11 | Pilot workload: IsaacGym robotic RL (4,096 environments) | Dr. Okonkwo's group | Policy convergence demonstrated |
| 11 | Pilot workload: Climate PINN on regional subset | Dr. Zhao's group | Physics loss convergence verified |
| 11--12 | Pilot workload: Medical segmentation (1,000 volume subset) | Dr. Venkataraman's group | Cascade training pipeline validated |
| 12 | User training workshops (2x half-day sessions, 40 attendees each) | ML engineer, student assistants | 80 researchers trained |
| 12 | **Phase 3 Gate Review:** All pilot workloads successful, users onboarded | PI, all co-PIs | Go/no-go for Phase 4 |

### 7.4 Phase 4: Full Production Operations (Months 13--36)

| Quarter | Activity | Key Milestones |
|---|---|---|
| Q5 (Mo 13--15) | Full production launch; SciLM-70B training begins | SciLM-70B training initiated |
| Q6 (Mo 16--18) | Federated learning testbed live with 2 partner institutions | First federated model trained |
| Q7 (Mo 19--21) | SciLM-70B training complete; fine-tuning and RLHF begins | Pre-trained model checkpoint released |
| Q8 (Mo 22--24) | All 4 partner institutions connected; medical segmentation FDA prep | Federated network fully operational |
| Q9 (Mo 25--27) | First annual performance review; hardware refresh assessment | Annual report submitted |
| Q10 (Mo 28--30) | Storage expansion if needed (additional OSS nodes) | Capacity maintained at < 80% utilization |
| Q11 (Mo 31--33) | Sustainability planning; grant renewal applications | Renewal proposals submitted |
| Q12 (Mo 34--36) | Final reporting; transition to ongoing operations model | Final project report; operations handoff |

---

## 8. Risk Assessment

The following risk register identifies the primary risks to project success, their likelihood and impact ratings, and proposed mitigation strategies.

### 8.1 Risk Register

| Risk ID | Risk Description | Likelihood | Impact | Risk Level | Mitigation Strategy |
|---|---|---|---|---|---|
| R1 | **GPU Supply Chain Delays:** NVIDIA H100 GPU availability may be constrained due to high demand from hyperscalers and sovereign AI initiatives, leading to delivery delays of 3--6 months. | High | High | **Critical** | (1) Place purchase orders immediately upon funding approval with contractual delivery guarantees and penalty clauses. (2) Identify secondary vendors (e.g., Lambda, CoreWeave rental as bridge). (3) Maintain Option B (A100) as fallback, as A100 availability is significantly better. |
| R2 | **Power Capacity Constraints:** The existing electrical infrastructure in Meridian Engineering Building may be insufficient to support the full 500 kW load, requiring utility-level upgrades with long lead times. | Medium | High | **High** | (1) Phase 1 includes comprehensive electrical assessment by licensed engineer. (2) Engage campus facilities early (pre-award) to initiate utility coordination. (3) Design for staged power deployment --- Phase 2 brings 4 nodes online first (200 kW), remaining 4 nodes in Phase 3. |
| R3 | **Cooling Infrastructure Challenges:** Direct liquid cooling systems require specialized plumbing and may encounter compatibility issues with existing building HVAC systems. | Medium | Medium | **Medium** | (1) Engage cooling vendor (CoolIT, GRC, or equivalent) during Phase 1 design to validate compatibility. (2) Include contingency budget for HVAC modifications. (3) Specify rear-door heat exchangers as backup cooling path if direct-to-chip cooling encounters delays. |
| R4 | **Staff Recruitment in Competitive Market:** Qualified HPC systems administrators and ML infrastructure engineers command premium salaries and may be difficult to recruit in the current market. | High | Medium | **High** | (1) Salary benchmarking against industry (FAANG, national labs) with competitive offers at 75th percentile. (2) Leverage university benefits (tuition remission, retirement, work-life balance) as differentiators. (3) Begin recruitment during Phase 1, before cluster is operational, to avoid gaps. (4) Cross-train existing IT staff as backup. |
| R5 | **Technology Obsolescence:** The 3-year project period may see significant GPU architecture advances (e.g., NVIDIA B100/B200, AMD MI400) that reduce the relative competitiveness of H100/A100 hardware. | Medium | Low | **Low** | (1) Hardware selection prioritizes currently available, production-proven technology over announced but unavailable future products. (2) Budget includes Year 2--3 hardware refresh allocation ($1M) for targeted upgrades. (3) Modular design enables incremental node replacement without full cluster rebuild. (4) Research value is determined by time-to-result, not hardware generation --- a cluster online in 2026 delivers results 2 years before a hypothetical next-gen cluster online in 2028. |
| R6 | **Budget Overrun:** Component costs may increase between proposal submission and procurement, particularly for GPUs and InfiniBand equipment. | Medium | Medium | **Medium** | (1) 4% contingency reserve ($500K) provides buffer. (2) Vendor negotiations will include price-lock provisions where available. (3) Option C (hybrid configuration) provides a lower-cost fallback if budget pressure materializes. |
| R7 | **Software Stack Complexity:** Integrating Slurm, Lustre, NVIDIA drivers, CUDA, container runtimes, and monitoring tools into a reliable production environment may require more effort than estimated. | Low | Medium | **Low-Medium** | (1) Leverage NVIDIA's NGC-ready reference architectures and validated configurations. (2) ML engineer hire will have demonstrated experience with HPC software stack deployment. (3) Phase 3 includes 4 months of dedicated testing and validation. |
| R8 | **Cybersecurity Incidents:** A high-value GPU cluster may be targeted for cryptojacking or used as a lateral movement target within the campus network. | Low | High | **Medium** | (1) Network segmentation with dedicated VLAN and firewall rules. (2) Multi-factor authentication for all user accounts. (3) Regular vulnerability scanning and patching cadence. (4) Integration with campus SOC monitoring. (5) No direct internet-facing services; access via SSH bastion host only. |

### 8.2 Risk Governance

The PI will maintain and review the risk register quarterly, with updates presented to the PNIT IT Governance Committee. Any risk escalation to "Critical" level will trigger an immediate review meeting with the Office of Research Administration and relevant stakeholders. The contingency reserve draw-down will be governed by a formal change control process requiring PI and co-PI consensus.

---

## 9. Success Metrics

The MHPACC project will be evaluated against the following quantitative and qualitative success metrics, measured at annual intervals and at project conclusion.

### 9.1 Research Output Metrics

| Metric | Year 1 Target | Year 2 Target | Year 3 Target | 3-Year Cumulative |
|---|---|---|---|---|
| Peer-reviewed publications enabled by MHPACC | 5 | 15 | 25 | 45 |
| Conference presentations and invited talks | 8 | 12 | 15 | 35 |
| Pre-trained models released to research community | 1 | 3 | 5 | 9 |
| Datasets curated and published | 2 | 4 | 6 | 12 |
| Graduate theses completed using MHPACC | 0 | 3 | 8 | 11 |
| Patents filed | 0 | 1 | 2 | 3 |

### 9.2 Computational Performance Metrics

| Metric | Target | Measurement Method |
|---|---|---|
| Sustained Training Throughput | > 45 PFLOPS (FP16) on flagship workloads | NCCL benchmarks + application-level MFU measurement |
| Peak Single-Node Performance | > 12 PFLOPS (FP16) per 8-GPU node | HPL-AI benchmark |
| Storage I/O Throughput | > 100 GB/s sequential read (aggregate) | IOR benchmark on Lustre |
| InfiniBand Fabric Latency | < 1.5 microseconds (node-to-node, unloaded) | ib_write_lat / ib_read_lat |
| Job Scheduler Efficiency | < 5 minute average queue wait time (non-preemptible) | Slurm sacct logs, monthly average |

### 9.3 Operational Metrics

| Metric | Target | Notes |
|---|---|---|
| GPU Utilization Rate | > 75% monthly average | Measured via DCGM (Data Center GPU Manager); excludes scheduled maintenance windows |
| System Availability | > 99.0% (excluding planned maintenance) | Target allows ~87 hours unplanned downtime per year |
| Planned Maintenance Windows | < 48 hours per quarter | Scheduled during academic breaks when possible |
| Mean Time to Recovery (MTTR) | < 4 hours for single-node failure | Requires on-site spare parts inventory and vendor SLA |
| Power Usage Effectiveness (PUE) | < 1.20 | Measured at the facility level, targeting best-in-class for university data centers |

### 9.4 Energy Efficiency Metrics

| Metric | Target | Benchmark |
|---|---|---|
| Performance per Watt (FP16 TFLOPS/W) | > 130 TFLOPS/W per H100 node | Based on published H100 SXM TDP of 700W and 1,979 TFLOPS peak |
| Annual Energy Consumption | < 2.5 GWh | Based on 350 kW average draw x 8,760 hours x 0.82 utilization factor |
| Carbon Footprint | < 500 metric tons CO2e per year | Based on Pacific Northwest grid carbon intensity (~0.2 kg CO2e/kWh) |
| Renewable Energy Offset | 100% by Year 3 | Via university renewable energy credit (REC) purchasing program |

### 9.5 Financial Sustainability Metrics

| Metric | Target | Notes |
|---|---|---|
| External Grant Funding Attracted | > $5M in new grants citing MHPACC as a resource | Tracked via grant proposal text search and PI reporting |
| Industry Partnership Revenue | > $200K per year by Year 3 | Paid access for industry research collaborations |
| Cost per GPU-Hour | < $2.50 (amortized) | Competitive with commercial cloud pricing for equivalent hardware |
| Total Cost of Ownership (3-year) | < $14M (including externalities) | Budget + estimated electricity costs (~$750K over 3 years at $0.10/kWh) |

### 9.6 User Satisfaction and Training

| Metric | Target | Measurement |
|---|---|---|
| User Satisfaction Score | > 4.0 / 5.0 | Annual user survey (Likert scale) |
| Active Users (monthly) | > 50 by Year 2 | Unique Slurm users per month |
| Training Workshop Attendance | > 100 attendees per year | Registration records |
| User Support Ticket Resolution Time | < 24 hours (business days) | Ticketing system metrics |

---

## 10. Appendices

### Appendix A: Letters of Support

Letters of support from the following stakeholders are attached as supplementary documents:

1. Dr. Michael Torres, Dean, College of Engineering, PNIT
2. Dr. Catherine Osei, Vice Provost for Research, PNIT
3. Mr. David Henriksen, Chief Information Officer, PNIT
4. Dr. Anna Kowalski, Director, Pacific Northwest Climate Research Consortium
5. Dr. Robert Chen, Chair, Department of Biomedical Engineering, University of Oregon (federated learning partner)

### Appendix B: Facility Site Plan

Architectural drawings for Room B-142, Meridian Engineering Building, including proposed rack layout, power distribution, and cooling infrastructure routing, are available upon request from the PNIT Facilities Management Office.

### Appendix C: Vendor Quotations

Preliminary quotations from the following vendors are on file with the PI and available for review:

- NVIDIA Corporation (DGX H100 systems, InfiniBand networking)
- Supermicro (alternative GPU server platforms)
- DDN Storage (Lustre appliances)
- CoolIT Systems (direct liquid cooling)
- Eaton Corporation (UPS systems)

### Appendix D: Current Research Group Publications

A selected bibliography of recent publications from the Meridian AI Research Lab, demonstrating the research impact and computational needs that motivate this proposal, is provided as a separate document.

---

**Submitted by:**

Dr. Evelyn R. Matsuda
Director, Meridian AI Research Lab
Pacific Northwest Institute of Technology
Email: ematsuda@pnit.edu
Phone: (503) 555-0147

**Institutional Endorsement:**

Dr. Catherine Osei
Vice Provost for Research
Pacific Northwest Institute of Technology

---

*This document is confidential and intended for internal review by the PNIT Research Infrastructure Committee. Distribution outside the committee requires written authorization from the PI.*
