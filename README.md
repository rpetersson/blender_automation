# VM Blender Automation

A comprehensive script for automating Blender rendering on a remote Ubuntu VM via SSH.

## Features

- 🔐 Secure SSH connection to Ubuntu VM
- 📦 Automatic Blender installation via snap
- 📁 File upload/download automation
- 🎬 Background Blender rendering
- � GPU-optimized multi-GPU rendering for NVIDIA GPUs
- �🔧 Flexible configuration options
- 🧹 Automatic cleanup
- 📊 Progress tracking and logging

## Quick Start

1. **Setup Configuration**
   ```bash
   cp config.env.example config.env
   # Edit config.env with your VM details
   ```

2. **Test SSH Connection**
   ```bash
   ./vm_blender_automation.sh --test-ssh
   ```

3. **Run a Simple Render**
   ```bash
   ./vm_blender_automation.sh -i ./input -o ./output -s render_script.py
   ```

## Installation

1. Clone or download the scripts to your local machine
2. Make scripts executable:
   ```bash
   chmod +x vm_blender_automation.sh
   chmod +x helpers.sh
   ```
3. Configure your VM connection details in `config.env`

## Configuration

Edit `config.env` with your specific settings:

```bash
# VM Connection (Required)
VM_HOST="192.168.1.100"      # Your VM's IP or hostname
VM_USER="ubuntu"             # Username on the VM
VM_KEY="/path/to/key.pem"    # SSH key file (optional)

# Directories
LOCAL_INPUT_DIR="./input"    # Local files to upload
LOCAL_OUTPUT_DIR="./output"  # Where to download results

# Blender Settings
BLENDER_FILE="scene.blend"   # Specific .blend file
BLENDER_SCRIPT="script.py"   # Python script to run
OUTPUT_FORMAT="PNG"          # Output format
FRAME_START=1               # Animation start frame
FRAME_END=250               # Animation end frame

# GPU Rendering Settings
USE_GPU_RENDERING=true      # Enable GPU-optimized rendering
GPU_COUNT=4                 # Number of GPUs to use
REQUIRE_SUDO=true           # GPU config requires sudo
```

## Usage Examples

### Single Image Render
```bash
./vm_blender_automation.sh -i ./assets -o ./renders -f my_scene.blend
```

### Animation Render
```bash
./vm_blender_automation.sh \
  -i ./assets \
  -o ./renders \
  -f animation.blend \
  --frame-start 1 \
  --frame-end 250 \
  --format EXR
```

### Script-Based Rendering
```bash
./vm_blender_automation.sh \
  -i ./input \
  -o ./output \
  -s procedural_render.py \
  --frame-start 1 \
  --frame-end 100
```

### GPU-Accelerated Rendering
```bash
./vm_blender_automation.sh \
  -i ./input \
  -o ./output \
  -f animation.blend \
  --gpu \
  --gpu-count 4 \
  --require-sudo \
  --frame-start 1 \
  --frame-end 1000
```

### Test SSH Connection Only
```bash
./vm_blender_automation.sh --test-ssh
```

## Command Line Options

| Option | Description | Example |
|--------|-------------|---------|
| `-h, --help` | Show help message | |
| `-c, --config FILE` | Config file path | `-c my_config.env` |
| `-i, --input DIR` | Input directory | `-i ./assets` |
| `-o, --output DIR` | Output directory | `-o ./renders` |
| `-f, --file FILE` | Blender file | `-f scene.blend` |
| `-s, --script FILE` | Python script | `-s render.py` |
| `--frame-start N` | Start frame | `--frame-start 1` |
| `--frame-end N` | End frame | `--frame-end 250` |
| `--format FORMAT` | Output format | `--format EXR` |
| `--gpu` | Enable GPU rendering | |
| `--gpu-count N` | Number of GPUs | `--gpu-count 4` |
| `--require-sudo` | GPU config needs sudo | |
| `--test-ssh` | Test SSH only | |
| `--no-cleanup` | Keep remote files | |

## File Structure

```
tauanscript/
├── vm_blender_automation.sh    # Main script
├── gpu_render.sh               # GPU-optimized rendering script
├── helpers.sh                  # Utility functions
├── config.env                  # Your configuration
├── config.env.example          # Configuration template
├── input/                      # Input files directory
│   ├── batch_cycles.py        # GPU rendering configuration script
│   ├── render_script.py       # Example Python script
│   └── README.md              # Input directory guide
├── output/                     # Output files directory
└── README.md                  # This file
```

## Workflow

1. **Connection Test**: Verifies SSH connectivity to your VM
2. **Blender Installation**: Installs Blender via snap if not present
3. **Directory Setup**: Creates working directories on the VM
4. **File Upload**: Transfers your local files to the VM
5. **Blender Execution**: Runs Blender in background mode
6. **File Download**: Downloads rendered files back to your machine
7. **Cleanup**: Removes temporary files from the VM (optional)

## Requirements

### Local Machine
- Bash shell (Linux/macOS/WSL)
- SSH client
- SCP for file transfer

### Remote VM
- Ubuntu (tested on 18.04+)
- SSH server running
- Sudo access for snap installation
- Internet connection for Blender download
- **For GPU rendering**: NVIDIA GPUs with CUDA support
- **For GPU rendering**: NVIDIA drivers and nvidia-smi installed

## Supported Output Formats

- PNG (default)
- JPEG
- EXR
- TIFF
- BMP
- HDR
- TARGA

## GPU Rendering

The script includes advanced GPU rendering capabilities for NVIDIA GPUs, enabling high-performance rendering with automatic workload distribution across multiple GPUs.

### GPU Rendering Features

- **Multi-GPU Support**: Automatically distributes frame rendering across multiple GPUs
- **GPU Optimization**: Configures NVIDIA GPU settings for optimal performance
- **Cycles Engine**: Optimized for Blender's Cycles rendering engine
- **Frame Distribution**: Intelligently splits frame ranges across available GPUs
- **Parallel Processing**: Renders multiple frame ranges simultaneously

### GPU Requirements

- NVIDIA GPUs with CUDA support
- NVIDIA drivers installed on the VM
- `nvidia-smi` utility available
- Sudo access (if `REQUIRE_SUDO=true`)

### GPU Configuration

Enable GPU rendering in your `config.env`:

```bash
USE_GPU_RENDERING=true
GPU_COUNT=4                 # Number of GPUs to use
REQUIRE_SUDO=true          # Set to true if GPU config needs sudo
```

Or use command line options:

```bash
./vm_blender_automation.sh --gpu --gpu-count 4 --require-sudo -f scene.blend
```

### How GPU Rendering Works

1. **GPU Detection**: Script checks for NVIDIA GPUs using `nvidia-smi`
2. **GPU Configuration**: Sets optimal GPU settings (persistent mode, clock speeds)
3. **Frame Distribution**: Calculates frame ranges for each GPU
4. **Parallel Rendering**: Launches multiple Blender instances, one per GPU
5. **Output Collection**: Collects rendered frames from all GPUs

### Performance Benefits

- **Speed**: Dramatically faster rendering with multiple GPUs
- **Efficiency**: Better GPU utilization compared to single-threaded rendering
- **Scalability**: Performance scales with number of available GPUs
- **Optimization**: Automatic GPU clock and memory settings

## Troubleshooting

### SSH Connection Issues
```bash
# Test SSH manually
ssh user@your-vm-ip

# Test with key file
ssh -i /path/to/key.pem user@your-vm-ip
```

### Permission Issues
```bash
# Make scripts executable
chmod +x vm_blender_automation.sh helpers.sh

# Check SSH key permissions
chmod 600 /path/to/your/key.pem
```

### Blender Installation Problems
```bash
# SSH to VM and install manually
ssh user@your-vm-ip
sudo snap install blender --classic
```

### File Transfer Issues
- Check local directory permissions
- Ensure VM has sufficient disk space
- Verify network connectivity

## Advanced Usage

### Custom Blender Commands
The script constructs Blender commands like:
```bash
blender -b input/scene.blend --python input/script.py -s 1 -e 250 -o output/render_#### -F PNG -a
```

### Environment Variables
You can override config values with environment variables:
```bash
VM_HOST="192.168.1.100" ./vm_blender_automation.sh --test-ssh
```

### Multiple VMs
Use different config files for different VMs:
```bash
./vm_blender_automation.sh -c vm1_config.env -i ./input -o ./output1
./vm_blender_automation.sh -c vm2_config.env -i ./input -o ./output2
```

## Security Notes

- Use SSH keys instead of passwords when possible
- Restrict SSH access to your IP range
- Consider using a dedicated user account for rendering
- Review the cleanup settings to avoid leaving files on the VM

## Performance Tips

- Use faster storage (SSD) on the VM for better performance
- Consider VM specs based on your rendering needs
- Use appropriate output formats (PNG for final, EXR for compositing)
- Monitor VM resources during rendering

## Support

For issues and questions:
1. Check the troubleshooting section
2. Verify your configuration with `--test-ssh`
3. Review the log output for error details
4. Test individual components (SSH, file transfer, Blender) separately# blender_automation
