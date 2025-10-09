# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

This is a VM-based Blender automation system that orchestrates GPU-accelerated 3D rendering on remote Ubuntu VMs. The system handles the complete workflow from SSH connection to VM, Blender installation/detection, file transfers, parallel GPU rendering, and output retrieval.

## Architecture

### Core Components

**Three Automation Scripts** (different Blender installation approaches):
- `manual_vm_blender_automation.sh` - Downloads and installs specific Blender version (4.5.3) from official releases
- `snap_vm_blender_automation.sh` - Uses snap package manager for Blender installation
- `use_existing_blender_automation.sh` - Detects and uses pre-installed Blender (any installation method)

**Configuration System**:
- `config.env` - Central configuration file for VM details, paths, and render settings
- Input/output directories with `.gitkeep` files for version control

**VM Workflow Architecture**:
1. SSH connection establishment and validation
2. Blender installation/detection phase
3. Remote directory preparation (`/tmp/blender_work/`)
4. File upload via SCP (input directory → VM)
5. GPU-aware parallel rendering with OPTIX acceleration
6. Compressed archive creation and download
7. Remote cleanup

### GPU Rendering Strategy

The system implements sophisticated GPU utilization:
- **Multi-GPU Frame Distribution**: Automatically splits frame ranges across available NVIDIA GPUs
- **GPU Detection**: Uses `nvidia-smi` queries to enumerate available GPUs
- **CUDA Device Isolation**: Sets `CUDA_VISIBLE_DEVICES` per render process
- **OPTIX Acceleration**: Forces `--cycles-device OPTIX` for maximum performance
- **Vulkan Compatibility**: Sets `BLENDER_USD_DISABLE_HYDRA=1` environment variable

## Common Development Commands

### Basic Rendering Operations

```bash
# Test SSH connectivity only
./manual_vm_blender_automation.sh --test-ssh

# Single frame render with custom port
./snap_vm_blender_automation.sh -i ./input -o ./output -f scene.blend -p 2222

# Animation sequence render (multi-GPU distribution)
./use_existing_blender_automation.sh -i ./input -o ./output -f animation.blend --frame-start 1 --frame-end 250

# Compressed output with local extraction
./manual_vm_blender_automation.sh -i ./input -o ./output -f scene.blend --compress --extract
```

### Configuration Management

```bash
# Edit VM configuration
vim config.env

# Validate configuration without running render
./snap_vm_blender_automation.sh --test-ssh -c ./custom_config.env
```

### Output Handling

```bash
# Compressed archive formats (tar.gz, zip, tar.bz2)
./manual_vm_blender_automation.sh -f scene.blend --compress --compression-format zip

# Skip remote cleanup for debugging
./use_existing_blender_automation.sh -f scene.blend --no-cleanup
```

## Configuration Requirements

### Essential config.env Settings

```bash
# VM Connection (Required)
VM_HOST="your.vm.ip.address"    # VM IP or hostname
VM_USER="root"                  # SSH username
VM_PORT="22"                    # SSH port
VM_KEY=""                       # Optional: SSH private key path

# Local Paths
LOCAL_INPUT_DIR="./input"       # Blender files location
LOCAL_OUTPUT_DIR="./output"     # Render output destination

# Remote Settings
REMOTE_WORK_DIR="/tmp/blender_work"    # VM working directory

# Render Configuration
BLENDER_FILE="scene.blend"      # Target .blend file
OUTPUT_FORMAT="PNG"             # Output format
FRAME_START=1                   # Animation start frame
FRAME_END=200                   # Animation end frame

# Performance Settings
CLEANUP_REMOTE=true             # Cleanup VM after completion
```

### GPU Requirements

- **NVIDIA GPU Support**: All scripts require NVIDIA GPUs with CUDA support
- **Driver Compatibility**: VM must have nvidia-smi available for GPU detection
- **OPTIX Support**: GPUs must support OPTIX ray tracing (RTX series recommended)

## Script Selection Guide

**Use `manual_vm_blender_automation.sh` when**:
- You need a specific Blender version (4.5.3)
- VM has no existing Blender installation
- Maximum control over Blender installation required

**Use `snap_vm_blender_automation.sh` when**:
- VM supports snap packages
- You want automatic updates and sandboxed environment
- Quick installation with minimal configuration

**Use `use_existing_blender_automation.sh` when**:
- Blender is already installed on VM
- You want to avoid reinstallation overhead
- Working with custom/compiled Blender builds

## Error Handling and Debugging

### Common Issues

**SSH Connection Failures**:
```bash
# Test connectivity first
./script_name.sh --test-ssh

# Check SSH configuration
ssh -p $VM_PORT $VM_USER@$VM_HOST "echo 'test'"
```

**GPU Detection Issues**:
```bash
# Verify GPU availability on VM
ssh $VM_USER@$VM_HOST "nvidia-smi"
```

**Blender Installation Problems**:
- Manual script: Check download URL accessibility and disk space
- Snap script: Verify snap daemon and permissions
- Existing script: Ensure Blender executable permissions

### Debugging Workflow

1. Run with `--test-ssh` first to validate connectivity
2. Check VM GPU status with direct SSH commands
3. Use `--no-cleanup` to preserve VM state for investigation
4. Monitor VM resources during large frame sequences

## Security Considerations

- SSH key authentication preferred over password-based access
- VM should have restricted network access if handling sensitive models
- Regular cleanup of `/tmp/blender_work` directory recommended
- Consider VPN tunneling for production rendering workflows