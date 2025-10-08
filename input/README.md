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

The script automatically treats matching start/end frames as a single still render and uses `-f` under the hood, while wider ranges trigger animation mode with `-s/-e -a`.

Remove unused files to keep uploads fast and conserve space on the VM.

Rendered frames will come back to your local `./output` directory with the pattern `render_####.<FORMAT>` once the job finishes.
