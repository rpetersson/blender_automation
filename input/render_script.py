import bpy
import os

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
material.node_tree.nodes.new(type='ShaderNodeOutputMaterial')

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
scene = bpy.context.scene
scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.image_settings.file_format = 'PNG'

# Set output path
scene.render.filepath = '/tmp/blender_work/output/render_'

print("Scene setup completed")