# GPU/CUDA Rendering Troubleshooting Guide

## Problem: Blender is using CPU instead of GPU

### Step 1: Run GPU Diagnostic on Your VM

Upload and run the diagnostic script on your VM:

```bash
# On your local machine
./vm_blender_automation.sh -i ./input -o ./output -s render_script.py

# OR manually SSH to your VM and run:
ssh -p 22 root@your-vm-ip
bash diagnose_gpu.sh
```

### Step 2: Check Diagnostic Output

Look for these issues:

#### ✗ **NVIDIA GPU Not Detected**
```
✗ nvidia-smi not found - NVIDIA drivers may not be installed
```

**Fix:**
```bash
# Install NVIDIA drivers on Ubuntu
sudo apt update
sudo apt install nvidia-driver-535  # Or latest version
sudo reboot

# Verify after reboot
nvidia-smi
```

#### ✗ **Blender Can't See CUDA Devices**
```
✗ CUDA: No devices
✗ OPTIX: No devices
```

**Possible causes:**
1. **Snap confinement** - Snap Blender may not have GPU access
2. **Wrong Blender build** - Snap version might not include CUDA
3. **Missing CUDA libraries**

**Fix Option 1: Give Snap GPU Access**
```bash
# Connect snap to GPU interfaces
sudo snap connect blender:hardware-observe
sudo snap connect blender:opengl
```

**Fix Option 2: Install Blender from PPA (Better GPU Support)**
```bash
# Remove snap version
sudo snap remove blender

# Add Blender PPA
sudo add-apt-repository ppa:thomas-schiex/blender
sudo apt update
sudo apt install blender

# Verify Blender can see GPU
blender -b --python-expr "import bpy; prefs = bpy.context.preferences; cycles = prefs.addons['cycles'].preferences; cycles.refresh_devices(); print([d.name for d in cycles.devices])"
```

**Fix Option 3: Download Official Blender Build**
```bash
# Remove snap
sudo snap remove blender

# Download and extract official build
cd /opt
sudo wget https://download.blender.org/release/Blender4.0/blender-4.0.2-linux-x64.tar.xz
sudo tar -xf blender-4.0.2-linux-x64.tar.xz
sudo ln -s /opt/blender-4.0.2-linux-x64/blender /usr/local/bin/blender

# Test
blender --version
```

### Step 3: Update vm_blender_automation.sh to Use Correct Blender

If you installed Blender outside snap, update the script:

```bash
# Change this line in vm_blender_automation.sh:
snap run blender -b

# To:
blender -b
```

### Step 4: Verify CUDA is Working

Run this test on your VM:

```bash
blender -b -E CYCLES --python-expr "
import bpy
prefs = bpy.context.preferences
cycles = prefs.addons['cycles'].preferences
cycles.compute_device_type = 'CUDA'
cycles.refresh_devices()
for device in cycles.devices:
    if device.type == 'CUDA':
        print(f'CUDA device: {device.name}')
        device.use = True
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'GPU'
print(f'Render device: {scene.cycles.device}')
" -- --cycles-device CUDA
```

### Step 5: Common Issues and Solutions

#### Issue: Snap Blender Can't Access GPU
**Solution:** Use official Blender build instead of snap

#### Issue: "CUDA compiler not found"
**Solution:** Install CUDA toolkit
```bash
sudo apt install nvidia-cuda-toolkit
```

#### Issue: GPU exists but Blender still uses CPU
**Solution:** Force CUDA in command line
```bash
blender -b scene.blend -E CYCLES -- --cycles-device CUDA -a
```

#### Issue: Multiple GPUs not being used
**Solution:** Use the GPU rendering script
```bash
./vm_blender_automation.sh --gpu --gpu-count 4 -f scene.blend
```

### Step 6: Verify Your VM Actually Has a GPU

```bash
lspci | grep -i nvidia
# Should show something like:
# 00:05.0 VGA compatible controller: NVIDIA Corporation TU104 [GeForce RTX 2080] (rev a1)
```

If nothing shows, your VM doesn't have a GPU!

### Cloud Provider GPU VM Setup

#### AWS EC2
- Use instance types: `g4dn.*`, `g5.*`, `p3.*`, `p4.*`
- AMI must be GPU-enabled (e.g., Deep Learning AMI)

#### Azure
- Use instance types: `NC*`, `ND*`, `NV*` series
- Install NVIDIA drivers after VM creation

#### Google Cloud
- Use instance types with GPU (e.g., `n1-standard-4` + `nvidia-tesla-t4`)
- Add GPU to existing VM or create GPU-enabled VM

### Recommended Solution

**For best GPU performance, use official Blender build instead of snap:**

1. Remove snap: `sudo snap remove blender`
2. Download from blender.org
3. Update script to use `blender` instead of `snap run blender`
4. Ensure NVIDIA drivers are installed
5. Test GPU access with diagnostic script