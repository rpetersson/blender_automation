import bpy
import sys

print("=" * 60)
print("Blender CUDA Rendering Script")
print("=" * 60)

# Configure Cycles render engine first
scene = bpy.context.scene
scene.render.engine = 'CYCLES'

# Configure CUDA - More aggressive approach
print("\nConfiguring GPU/CUDA...")
prefs = bpy.context.preferences
cycles_prefs = prefs.addons['cycles'].preferences

# Show current preferences
print(f"Current compute device type: {cycles_prefs.compute_device_type}")

# Try different compute device types in order of preference
device_type_found = False
selected_device_type = None

for device_type in ['CUDA', 'OPTIX', 'OPENCL', 'HIP']:
    try:
        print(f"\nTrying {device_type}...")
        cycles_prefs.compute_device_type = device_type
        cycles_prefs.refresh_devices()
        
        # List ALL devices
        print(f"  Total devices found: {len(cycles_prefs.devices)}")
        for i, device in enumerate(cycles_prefs.devices):
            print(f"    [{i}] {device.name} (Type: {device.type}, Use: {device.use})")
        
        # Check if this device type has any devices
        available_devices = [d for d in cycles_prefs.devices if d.type == device_type]
        if available_devices:
            print(f"  ✓ Found {len(available_devices)} {device_type} device(s)")
            
            # Enable all devices of this type
            for device in available_devices:
                device.use = True
                print(f"    ✓ Enabled: {device.name}")
            
            device_type_found = True
            selected_device_type = device_type
            break
        else:
            print(f"  ✗ No {device_type} devices available")
    except Exception as e:
        print(f"  ✗ {device_type} error: {e}")

if device_type_found:
    scene.cycles.device = 'GPU'
    print(f"\n✓ GPU rendering enabled with {selected_device_type}")
else:
    print("\n✗ No GPU devices found, using CPU")
    scene.cycles.device = 'CPU'
    print("\nPossible reasons:")
    print("  1. NVIDIA drivers not installed on VM")
    print("  2. Blender not compiled with CUDA support")
    print("  3. VM doesn't have an NVIDIA GPU")
    print("  4. Snap confinement preventing GPU access")

# Clear existing mesh objects
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False, confirm=False)

# Create a simple scene with a cube
bpy.ops.mesh.primitive_cube_add(location=(0, 0, 0))
cube = bpy.context.active_object

# Add material
material = bpy.data.materials.new(name="CubeMaterial")
material.use_nodes = True
material.node_tree.nodes.clear()

# Add Principled BSDF
bsdf = material.node_tree.nodes.new(type='ShaderNodeBsdfPrincipled')
output = material.node_tree.nodes.new(type='ShaderNodeOutputMaterial')

# Connect nodes
material.node_tree.links.new(bsdf.outputs[0], output.inputs[0])

# Set material color to blue
bsdf.inputs[0].default_value = (0.0, 0.0, 1.0, 1.0)  # Blue

# Assign material to cube
cube.data.materials.append(material)

# Add a light
bpy.ops.object.light_add(type='SUN', location=(2, 2, 5))

# Position camera
camera = bpy.data.objects['Camera']
camera.location = (4, -4, 3)
camera.rotation_euler = (1.1, 0, 0.785)

# Set render settings
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.image_settings.file_format = 'PNG'

# Cycles settings
scene.cycles.samples = 64  # Reduced for faster testing
scene.cycles.use_denoising = True

# Set output path
scene.render.filepath = '/tmp/blender_work/output/render_'

print("Scene setup completed")
print(f"Render engine: {scene.render.engine}")
print(f"Render device: {scene.cycles.device}")
print(f"Samples: {scene.cycles.samples}")
print(f"Output path: {scene.render.filepath}")

# Force render the current frame
print("Starting render...")
bpy.ops.render.render(write_still=True)
print("Render completed!")