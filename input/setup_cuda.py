import bpy
import sys

"""
This script sets up CUDA for Blender rendering.
Run this before your main render script to ensure GPU acceleration is enabled.
"""

def setup_cuda():
    """Configure Blender to use CUDA GPUs"""
    print("=" * 60)
    print("CUDA Setup Script")
    print("=" * 60)
    
    # Get preferences
    prefs = bpy.context.preferences
    cycles_prefs = prefs.addons['cycles'].preferences
    
    # Set compute device type
    print("\nAvailable compute device types:")
    print(f"  - Current: {cycles_prefs.compute_device_type}")
    
    # Try CUDA first, then OPTIX, then fall back to CPU
    for device_type in ['CUDA', 'OPTIX', 'OPENCL']:
        try:
            cycles_prefs.compute_device_type = device_type
            cycles_prefs.refresh_devices()
            print(f"  - Trying {device_type}...")
            
            devices = cycles_prefs.devices
            gpu_devices = [d for d in devices if d.type in ['CUDA', 'OPTIX', 'OPENCL']]
            
            if gpu_devices:
                print(f"  ✓ {device_type} is available!")
                break
        except Exception as e:
            print(f"  ✗ {device_type} failed: {e}")
            continue
    else:
        print("  ✗ No GPU compute devices available, will use CPU")
        return False
    
    # Display all available devices
    print("\nAvailable devices:")
    for i, device in enumerate(cycles_prefs.devices):
        print(f"  [{i}] {device.name} ({device.type}) - Use: {device.use}")
    
    # Enable all GPU devices
    gpu_count = 0
    for device in cycles_prefs.devices:
        if device.type in ['CUDA', 'OPTIX', 'OPENCL']:
            device.use = True
            gpu_count += 1
            print(f"  ✓ Enabled: {device.name}")
    
    if gpu_count == 0:
        print("\n✗ No GPU devices found!")
        return False
    
    # Configure scene to use GPU
    scene = bpy.context.scene
    scene.cycles.device = 'GPU'
    
    print(f"\n✓ CUDA setup complete!")
    print(f"  - Compute device type: {cycles_prefs.compute_device_type}")
    print(f"  - GPU devices enabled: {gpu_count}")
    print(f"  - Render device: {scene.cycles.device}")
    print("=" * 60)
    
    return True

if __name__ == "__main__":
    success = setup_cuda()
    if not success:
        print("\nWARNING: GPU acceleration not available, rendering will use CPU")
        sys.exit(1)
