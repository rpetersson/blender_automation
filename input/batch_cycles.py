import bpy
import sys

# Get GPU ID from command line arguments
gpu_id = int(sys.argv[-1]) if sys.argv[-1].isdigit() else 0

# Configure Cycles render engine for GPU rendering
scene = bpy.context.scene
scene.render.engine = 'CYCLES'

# Get Cycles preferences
cycles_prefs = bpy.context.preferences.addons['cycles'].preferences

# Enable GPU compute
cycles_prefs.compute_device_type = 'CUDA'  # or 'OPENCL' or 'OPTIX'

# Enable all available GPUs or specific GPU
for device in cycles_prefs.devices:
    if device.type == 'CUDA':  # or 'OPENCL'
        device.use = True

# Set render device to GPU
scene.cycles.device = 'GPU'

# Optimize render settings for GPU
scene.cycles.samples = 128  # Adjust as needed
scene.cycles.use_denoising = True
scene.cycles.denoiser = 'OIDN'

# Set tile size for GPU rendering
if hasattr(scene.render, 'tile_x'):
    scene.render.tile_x = 256
    scene.render.tile_y = 256

print(f"Configured Cycles for GPU {gpu_id} rendering")
print(f"Device: {scene.cycles.device}")
print(f"Samples: {scene.cycles.samples}")
print(f"Denoising: {scene.cycles.use_denoising}")

# Set output path with GPU ID to avoid conflicts
base_path = scene.render.filepath
if not base_path.endswith('_'):
    base_path += '_'
scene.render.filepath = f"{base_path}gpu{gpu_id}_"

print(f"Output path: {scene.render.filepath}")