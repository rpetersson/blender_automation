import bpy

# Clear existing mesh objects
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False, confirm=False)

# Enable CUDA for rendering
scene = bpy.context.scene
scene.render.engine = 'CYCLES'

# Configure CUDA preferences
prefs = bpy.context.preferences
cycles_prefs = prefs.addons['cycles'].preferences

# Set compute device type to CUDA
cycles_prefs.compute_device_type = 'CUDA'

# Enable all CUDA devices
for device in cycles_prefs.devices:
    if device.type == 'CUDA':
        device.use = True
        print(f"Enabled CUDA device: {device.name}")

# Set render device to GPU
scene.cycles.device = 'GPU'

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

# Set render settings optimized for GPU
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.image_settings.file_format = 'PNG'

# GPU-optimized Cycles settings
scene.cycles.samples = 128
scene.cycles.use_denoising = True
scene.cycles.denoiser = 'OIDN'

# Set tile size for GPU rendering
if hasattr(scene.render, 'tile_x'):
    scene.render.tile_x = 256
    scene.render.tile_y = 256

# Set output path
scene.render.filepath = '/tmp/blender_work/output/render_'

print("Scene setup completed with CUDA acceleration")
print(f"Render device: {scene.cycles.device}")
print(f"Compute device type: {cycles_prefs.compute_device_type}")
print(f"Samples: {scene.cycles.samples}")
print(f"Denoising: {scene.cycles.use_denoising}")
print(f"Output path: {scene.render.filepath}")