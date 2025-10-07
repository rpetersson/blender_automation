# Example Blender Files

This directory contains example files for testing the VM Blender automation script.

## Files

- `render_script.py`: A simple Python script that creates a basic scene with a blue cube and renders it
- `README.md`: This file

## Usage

To test with the example script:

```bash
./vm_blender_automation.sh -i ./input -o ./output -s render_script.py
```

## Creating Your Own Files

You can add your own .blend files and Python scripts to this directory. The automation script will upload all files in the input directory to the VM.

### Blend Files
Place your .blend files here and specify them with the `-f` or `--file` option:

```bash
./vm_blender_automation.sh -i ./input -o ./output -f your_scene.blend
```

### Python Scripts
Create Python scripts that use the Blender API (bpy) and specify them with the `-s` or `--script` option:

```bash
./vm_blender_automation.sh -i ./input -o ./output -s your_script.py
```

### Animation Rendering
For animations, specify frame ranges:

```bash
./vm_blender_automation.sh -i ./input -o ./output -f animation.blend --frame-start 1 --frame-end 250
```