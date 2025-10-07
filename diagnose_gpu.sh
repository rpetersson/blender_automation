#!/bin/bash

# CUDA/GPU Diagnostic Script
# Run this on your VM to check GPU availability

echo "=========================================="
echo "GPU/CUDA Diagnostic Check"
echo "=========================================="
echo

# Check for NVIDIA GPU
echo "1. Checking for NVIDIA GPU..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi
    echo "✓ NVIDIA GPU detected"
else
    echo "✗ nvidia-smi not found - NVIDIA drivers may not be installed"
fi
echo

# Check CUDA version
echo "2. Checking CUDA version..."
if command -v nvcc &> /dev/null; then
    nvcc --version
    echo "✓ CUDA toolkit installed"
else
    echo "✗ CUDA toolkit not found"
fi
echo

# Check Blender installation
echo "3. Checking Blender..."
if command -v blender &> /dev/null; then
    blender --version
    echo "✓ Blender found in PATH"
elif snap list blender &> /dev/null; then
    snap run blender --version
    echo "✓ Blender installed via snap"
else
    echo "✗ Blender not found"
fi
echo

# Check if Blender can see CUDA devices
echo "4. Checking if Blender can detect CUDA devices..."
cat > /tmp/check_cuda.py << 'EOF'
import bpy

prefs = bpy.context.preferences
cycles_prefs = prefs.addons['cycles'].preferences

print("\nAvailable compute device types:")
for device_type in ['CUDA', 'OPTIX', 'OPENCL', 'HIP', 'METAL']:
    try:
        cycles_prefs.compute_device_type = device_type
        cycles_prefs.refresh_devices()
        devices = [d for d in cycles_prefs.devices if d.type == device_type]
        if devices:
            print(f"  ✓ {device_type}: {len(devices)} device(s)")
            for d in devices:
                print(f"    - {d.name}")
        else:
            print(f"  ✗ {device_type}: No devices")
    except Exception as e:
        print(f"  ✗ {device_type}: {e}")
EOF

if snap list blender &> /dev/null; then
    snap run blender -b --python /tmp/check_cuda.py
elif command -v blender &> /dev/null; then
    blender -b --python /tmp/check_cuda.py
else
    echo "Cannot run Blender diagnostic"
fi

rm -f /tmp/check_cuda.py

echo
echo "=========================================="
echo "Diagnostic complete"
echo "=========================================="