import bpy

# Clear existing mesh objects
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False, confirm=False)

# Configure Cycles render engine first
scene = bpy.context.scene
scene.render.engine = 'CYCLES'

# Try to configure CUDA (but don't fail if it's not available)
try:
    prefs = bpy.context.preferences
    cycles_prefs = prefs.addons['cycles'].preferences
    
    # Check if CUDA is available
    cycles_prefs.refresh_devices()
    cuda_devices = [device for device in cycles_prefs.devices if device.type == 'CUDA']
    
    if cuda_devices:
        print(f"Found {len(cuda_devices)} CUDA device(s)")
        cycles_prefs.compute_device_type = 'CUDA'
        
        # Enable CUDA devices
        for device in cuda_devices:
            device.use = True
            print(f"Enabled CUDA device: {device.name}")
        
        scene.cycles.device = 'GPU'
        print("CUDA acceleration enabled")
    else:
        print("No CUDA devices found, using CPU")
        scene.cycles.device = 'CPU'
        
except Exception as e:
    print(f"CUDA setup failed: {e}")
    print("Falling back to CPU rendering")
    scene.cycles.device = 'CPU'

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