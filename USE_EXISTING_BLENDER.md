# Use Existing Blender Installation Script

## Overview
`use_existing_blender_automation.sh` is a lightweight version that uses whatever Blender installation is already present on the VM. It **does not install or update** Blender.

## Key Differences from Other Scripts

| Feature | manual_vm_blender_automation.sh | snap_vm_blender_automation.sh | use_existing_blender_automation.sh |
|---------|--------------------------------|-------------------------------|-----------------------------------|
| Blender Installation | ✅ Downloads & installs 4.5.3 | ✅ Installs via snap | ❌ Uses existing only |
| Installation Time | ~3-5 minutes | ~2-3 minutes | 0 seconds |
| Version Control | ✅ Guaranteed 4.5.3 | ⚠ Latest snap version | ❌ Uses whatever exists |
| Best For | Production, specific version | Quick setup | Pre-configured VMs |

## How It Works

### 1. Blender Detection
The script automatically searches for Blender in common locations:
- `/opt/blender/blender` (manual install)
- `/usr/local/bin/blender` (system install)
- `/usr/bin/blender` (package manager)
- `snap run blender` (snap install)
- Any blender in `$PATH`

### 2. Version Display
Shows the detected Blender version:
```
[INFO] Found Blender: Blender 4.5.3
[INFO] Executable: /opt/blender/blender
```

### 3. Error Handling
If no Blender is found, provides clear error:
```
[ERROR] No Blender installation found on VM!
[ERROR] Checked locations:
  - /opt/blender/blender
  - /usr/local/bin/blender
  - /usr/bin/blender
  - snap (snap run blender)

Please install Blender on the VM first, or use manual_vm_blender_automation.sh
```

## Usage

### Basic Command
```bash
./use_existing_blender_automation.sh \
  -i ./input \
  -o ./output \
  -f scene.blend \
  --frame-start 1 \
  --frame-end 100
```

### All Options
Same as other scripts:
```bash
./use_existing_blender_automation.sh [OPTIONS]

Options:
    -i, --input DIR         Local input directory
    -o, --output DIR        Local output directory
    -f, --file FILE         Blender file to render
    --frame-start N         Start frame
    --frame-end N           End frame
    --format FORMAT         Output format (png, exr, etc.)
    --compress              Compress output
    --test-ssh              Test connection only
```

## When to Use This Script

### ✅ Use When:
- VM already has Blender installed
- Using custom Blender build
- Using Docker image with Blender
- Vast.ai template includes Blender
- Want fastest startup time
- Don't care about specific version

### ❌ Don't Use When:
- Fresh VM without Blender
- Need specific Blender version
- Want guaranteed compatibility
- Production rendering (use manual install)

## Integration with Vast.ai

### Option 1: Pre-installed Template
```bash
# 1. Create Vast.ai instance with Blender template
./automate_vast_ai.sh

# 2. Use existing Blender
./use_existing_blender_automation.sh -i ./input -o ./output -f scene.blend
```

### Option 2: Custom Docker Image
If your Vast.ai instance uses a Docker image with Blender:
```bash
# The script will detect Blender in the container
./use_existing_blender_automation.sh -i ./input -o ./output -f scene.blend
```

## Performance

### Startup Time Comparison
- **manual_vm_blender_automation.sh**: 3-5 minutes (download + extract)
- **snap_vm_blender_automation.sh**: 2-3 minutes (snap install)
- **use_existing_blender_automation.sh**: 5-10 seconds (detection only)

### GPU Rendering
Same GPU optimization as other scripts:
- ✅ Requires GPU (no CPU fallback)
- ✅ Forces OPTIX rendering
- ✅ Multi-GPU support
- ✅ Parallel frame rendering

## Detected Blender Types

The script works with any Blender installation method:

### 1. Manual Installation
```bash
# Example: Blender installed to /opt/blender
[INFO] Found Blender: Blender 4.5.3
[INFO] Executable: /opt/blender/blender
```

### 2. Snap Installation
```bash
# Example: Snap Blender
[INFO] Found Blender: Blender 4.2.0
[INFO] Executable: snap run blender
```

### 3. System Package
```bash
# Example: apt install blender
[INFO] Found Blender: Blender 3.6.0
[INFO] Executable: /usr/bin/blender
```

### 4. Custom Build
```bash
# Example: Self-compiled Blender
[INFO] Found Blender: Blender 4.6.0-dev
[INFO] Executable: /usr/local/bin/blender
```

## Troubleshooting

### Error: No Blender Installation Found
**Solution 1**: Install Blender manually on VM
```bash
ssh root@<vm_host> "wget https://download.blender.org/release/Blender4.5/blender-4.5.3-linux-x64.tar.xz"
ssh root@<vm_host> "tar -xf blender-4.5.3-linux-x64.tar.xz -C /opt"
ssh root@<vm_host> "mv /opt/blender-4.5.3-linux-x64 /opt/blender"
```

**Solution 2**: Use different script
```bash
# If VM doesn't have Blender, use manual install script
./manual_vm_blender_automation.sh -i ./input -o ./output -f scene.blend
```

### Error: Blender Version Too Old
If detected Blender is outdated:
```bash
# Use manual install to get specific version
./manual_vm_blender_automation.sh -i ./input -o ./output -f scene.blend
```

### Error: Permission Denied
If Blender executable lacks permissions:
```bash
ssh root@<vm_host> "chmod +x /opt/blender/blender"
```

## Workflow Comparison

### Standard Workflow (with installation)
```
1. SSH connection      (5s)
2. Install Blender     (180s)  ← Time consuming
3. Upload files        (30s)
4. Render              (variable)
5. Download output     (60s)
Total: ~275s + render time
```

### Existing Blender Workflow
```
1. SSH connection      (5s)
2. Check Blender       (5s)    ← Much faster!
3. Upload files        (30s)
4. Render              (variable)
5. Download output     (60s)
Total: ~100s + render time
```

**Savings: 175 seconds per run!**

## Best Practices

### 1. Verify Blender First
Before starting big render:
```bash
# Test SSH and check Blender version
./use_existing_blender_automation.sh --test-ssh

# Then check what version is installed
ssh root@<vm_host> "blender --version"
```

### 2. Compatibility Check
Ensure your .blend file works with detected version:
```bash
# Test render single frame first
./use_existing_blender_automation.sh \
  -i ./input \
  -o ./output \
  -f scene.blend \
  --frame-start 1 \
  --frame-end 1
```

### 3. Use with Vast.ai Templates
Create custom Vast.ai template with:
- Ubuntu 22.04
- NVIDIA Drivers
- Blender 4.5.3 pre-installed
- CUDA/OPTIX ready

Then use this script for **instant rendering** without installation overhead.

## Example: Complete Workflow

```bash
# 1. Provision VM with Vast.ai (already has Blender)
./automate_vast_ai.sh
# Output: SSH info (save this)

# 2. Update config.env with VM details
vim config.env
# Set VM_HOST, VM_USER, etc.

# 3. Render using existing Blender (no installation!)
./use_existing_blender_automation.sh \
  -i ./input \
  -o ./output \
  -f animation.blend \
  --frame-start 1 \
  --frame-end 250

# 4. Results downloaded to ./output/
ls -lh output/
```

## Summary

**use_existing_blender_automation.sh** is the fastest option when:
- ✅ Blender is already installed on VM
- ✅ You don't need a specific version
- ✅ You want minimal setup time
- ✅ You're using pre-configured templates

For production work with version control, use `manual_vm_blender_automation.sh` instead.
