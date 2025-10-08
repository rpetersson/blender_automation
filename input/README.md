# Input Directory

Place your `.blend` projects and any supporting assets (textures, caches, etc.) in this folder. Everything inside will be uploaded to the VM before rendering begins.

## Recommended steps

1. Copy your `.blend` file(s) here.
2. Add all external resources the blend file depends on.
3. Run the automation script:

```bash
./vm_blender_automation.sh -i ./input -o ./output -f your_scene.blend
```

For animations, specify the frame range:

```bash
./vm_blender_automation.sh -i ./input -o ./output -f animation.blend --frame-start 1 --frame-end 250
```

Remove unused files to keep uploads fast and conserve space on the VM.
