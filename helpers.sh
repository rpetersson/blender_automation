#!/bin/bash

# Helper functions for VM Blender Automation
# This script contains utility functions for validation and setup

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validate configuration
validate_config() {
    local config_file="$1"
    local errors=0
    
    echo "Validating configuration..."
    
    if [[ ! -f "$config_file" ]]; then
        echo -e "${RED}Error: Configuration file $config_file not found${NC}"
        return 1
    fi
    
    # Source the config file
    # shellcheck source=/dev/null
    source "$config_file"
    
    # Check required fields
    if [[ -z "$VM_HOST" ]]; then
        echo -e "${RED}Error: VM_HOST is required${NC}"
        errors=$((errors + 1))
    fi
    
    if [[ -z "$VM_USER" ]]; then
        echo -e "${RED}Error: VM_USER is required${NC}"
        errors=$((errors + 1))
    fi
    
    # Check SSH key file if specified
    if [[ -n "$VM_KEY" && ! -f "$VM_KEY" ]]; then
        echo -e "${RED}Error: SSH key file $VM_KEY not found${NC}"
        errors=$((errors + 1))
    fi
    
    # Check local directories
    if [[ -n "$LOCAL_INPUT_DIR" && ! -d "$LOCAL_INPUT_DIR" ]]; then
        echo -e "${YELLOW}Warning: Input directory $LOCAL_INPUT_DIR does not exist${NC}"
    fi
    
    # Validate frame range
    if [[ "$FRAME_END" -lt "$FRAME_START" ]]; then
        echo -e "${RED}Error: FRAME_END ($FRAME_END) must be >= FRAME_START ($FRAME_START)${NC}"
        errors=$((errors + 1))
    fi
    
    # Validate output format
    local valid_formats=("PNG" "JPEG" "EXR" "TIFF" "BMP" "HDR" "TARGA")
    local format_valid=false
    for format in "${valid_formats[@]}"; do
        if [[ "${OUTPUT_FORMAT^^}" == "$format" ]]; then
            format_valid=true
            break
        fi
    done
    
    if [[ "$format_valid" == false ]]; then
        echo -e "${YELLOW}Warning: Output format $OUTPUT_FORMAT may not be supported${NC}"
        echo "Supported formats: ${valid_formats[*]}"
    fi
    
    if [[ $errors -eq 0 ]]; then
        echo -e "${GREEN}Configuration validation passed${NC}"
        return 0
    else
        echo -e "${RED}Configuration validation failed with $errors error(s)${NC}"
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    local missing_deps=()
    
    echo "Checking prerequisites..."
    
    # Check for required commands
    if ! command -v ssh >/dev/null 2>&1; then
        missing_deps+=("ssh")
    fi
    
    if ! command -v scp >/dev/null 2>&1; then
        missing_deps+=("scp")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing dependencies and try again."
        return 1
    fi
    
    echo -e "${GREEN}Prerequisites check passed${NC}"
    return 0
}

# Setup local directories
setup_local_directories() {
    local input_dir="$1"
    local output_dir="$2"
    
    echo "Setting up local directories..."
    
    # Create input directory if specified and doesn't exist
    if [[ -n "$input_dir" ]]; then
        if [[ ! -d "$input_dir" ]]; then
            echo "Creating input directory: $input_dir"
            mkdir -p "$input_dir" || {
                echo -e "${RED}Error: Failed to create input directory${NC}"
                return 1
            }
        fi
    fi
    
    # Create output directory if specified and doesn't exist
    if [[ -n "$output_dir" ]]; then
        if [[ ! -d "$output_dir" ]]; then
            echo "Creating output directory: $output_dir"
            mkdir -p "$output_dir" || {
                echo -e "${RED}Error: Failed to create output directory${NC}"
                return 1
            }
        fi
    fi
    
    echo -e "${GREEN}Local directories setup completed${NC}"
    return 0
}

# Display system information
show_system_info() {
    echo -e "${BLUE}System Information:${NC}"
    echo "OS: $(uname -s)"
    echo "Architecture: $(uname -m)"
    echo "Date: $(date)"
    
    if command -v ssh >/dev/null 2>&1; then
        echo "SSH version: $(ssh -V 2>&1 | head -n1)"
    fi
    
    echo ""
}

# Generate example files
create_example_files() {
    local input_dir="$1"
    
    if [[ -z "$input_dir" ]]; then
        input_dir="./input"
    fi
    
    echo "Creating example files in $input_dir..."
    
    mkdir -p "$input_dir"
    
    # Create a simple Blender Python script
    cat > "$input_dir/render_script.py" << 'EOF'
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
EOF
    
    # Create README for examples
    cat > "$input_dir/README.md" << 'EOF'
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
EOF
    
    echo -e "${GREEN}Example files created in $input_dir${NC}"
}

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    
    printf "\rProgress: ["
    printf "%${completed}s" | tr ' ' '='
    printf "%$((width - completed))s" | tr ' ' '-'
    printf "] %d%%" $percentage
}

# Test network connectivity
test_network() {
    local host="$1"
    
    echo "Testing network connectivity to $host..."
    
    if ping -c 1 -W 5 "$host" >/dev/null 2>&1; then
        echo -e "${GREEN}Network connectivity test passed${NC}"
        return 0
    else
        echo -e "${RED}Network connectivity test failed${NC}"
        echo "Cannot reach $host. Please check your network connection and VM status."
        return 1
    fi
}

# Estimate transfer time
estimate_transfer_time() {
    local directory="$1"
    local connection_speed="$2"  # in Mbps, default 100
    
    if [[ -z "$connection_speed" ]]; then
        connection_speed=100
    fi
    
    if [[ ! -d "$directory" ]]; then
        return 0
    fi
    
    local total_size
    total_size=$(du -sb "$directory" 2>/dev/null | cut -f1)
    
    if [[ -n "$total_size" && "$total_size" -gt 0 ]]; then
        local size_mb=$((total_size / 1024 / 1024))
        local time_seconds=$((size_mb * 8 / connection_speed))
        
        echo "Estimated transfer time: ${time_seconds}s for ${size_mb}MB"
    fi
}