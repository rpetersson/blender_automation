# Blender Installation Methods

## Overview

The script supports three installation methods for Blender. Choose based on your needs:

## 1. Snap Installation (Default)

**Command:** `sudo snap install blender --classic`

**Configure:**
```bash
# In config.env
BLENDER_INSTALL_METHOD="snap"
```

### Pros:
- ✅ Fast and automatic
- ✅ Easy to install
- ✅ Officially supported by Ubuntu

### Cons:
- ❌ **Often blocks GPU access** due to snap sandboxing
- ❌ May not have latest CUDA support
- ❌ Can have permission issues

### When to use:
- Testing or CPU-only rendering
- Quick setup
- No GPU needed

---

## 2. Official Blender Build (Recommended for GPU)

**Download:** From blender.org

**Configure:**
```bash
# In config.env
BLENDER_INSTALL_METHOD="official"
```

### Pros:
- ✅ **Full GPU/CUDA support**
- ✅ No sandboxing restrictions
- ✅ Latest features and optimizations
- ✅ Better performance

### Cons:
- ❌ Slightly longer install time
- ❌ Manual installation

### When to use:
- **GPU rendering required** (RECOMMENDED)
- Best performance needed
- CUDA acceleration important

**This installs Blender 4.0.2 to `/opt/` and creates a symlink in `/usr/local/bin/`**

---

## 3. Skip Installation

**Configure:**
```bash
# In config.env
BLENDER_INSTALL_METHOD="skip"
```

### When to use:
- Blender already manually installed on VM
- Using custom Blender build
- VM has pre-configured Blender

---

## Quick Comparison

| Feature | Snap | Official | Skip |
|---------|------|----------|------|
| GPU Support | ⚠️ Limited | ✅ Full | 🤷 Depends |
| Install Speed | ⚡ Fast | 🐢 Moderate | ⚡ Instant |
| CUDA Support | ⚠️ Maybe | ✅ Yes | 🤷 Depends |
| Auto Setup | ✅ Yes | ✅ Yes | ❌ No |
| Recommended | CPU only | **GPU rendering** | Pre-installed |

---

## Recommendation

### For GPU/CUDA Rendering:
```bash
BLENDER_INSTALL_METHOD="official"
```

### For Quick Testing (CPU):
```bash
BLENDER_INSTALL_METHOD="snap"
```

### If Blender Already Installed:
```bash
BLENDER_INSTALL_METHOD="skip"
```

---

## How to Change

Edit `config.env`:
```bash
# Before (default - may have GPU issues)
BLENDER_INSTALL_METHOD="snap"

# After (best for GPU rendering)
BLENDER_INSTALL_METHOD="official"
```

Then run:
```bash
./vm_blender_automation.sh -i ./input -o ./output -s render_script.py
```

---

## Manual Installation (Alternative)

If you want to install Blender manually on your VM:

```bash
# SSH to your VM
ssh root@your-vm-ip

# Remove snap version if exists
sudo snap remove blender

# Download official build
cd /tmp
wget https://download.blender.org/release/Blender4.0/blender-4.0.2-linux-x64.tar.xz
sudo tar -xf blender-4.0.2-linux-x64.tar.xz -C /opt/
sudo ln -s /opt/blender-4.0.2-linux-x64/blender /usr/local/bin/blender

# Verify
blender --version

# Then in config.env
BLENDER_INSTALL_METHOD="skip"
```