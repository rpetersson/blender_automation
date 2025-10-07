#!/bin/bash

# VM Blender Automation Script
# This script automates the process of:
# 1. SSH into Ubuntu VM
# 2. Install Blender via snap
# 3. Upload local files to VM
# 4. Run Blender in background mode
# 5. Download output files back to local machine

set -e  # Exit on any error

# Configuration file path
CONFIG_FILE="./config.env"

# Default values
VM_HOST=""
VM_USER="root"
VM_PORT="22"
VM_KEY=""
LOCAL_INPUT_DIR=""
LOCAL_OUTPUT_DIR=""
REMOTE_WORK_DIR="/tmp/blender_work"
BLENDER_INSTALL_METHOD="snap"
BLENDER_SCRIPT=""
OUTPUT_FORMAT="png"
FRAME_START=1
FRAME_END=1
USE_GPU_RENDERING=false
GPU_COUNT=1
REQUIRE_SUDO=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file $CONFIG_FILE not found!"
        info "Please create a config.env file with your VM details."
        info "See config.env.example for reference."
        exit 1
    fi
    
    source "$CONFIG_FILE"
    
    # Validate required variables
    if [[ -z "$VM_HOST" || -z "$VM_USER" ]]; then
        error "VM_HOST and VM_USER must be set in config.env"
        exit 1
    fi
}

# Test SSH connection
test_ssh_connection() {
    log "Testing SSH connection to $VM_USER@$VM_HOST:$VM_PORT..."
    
    local ssh_cmd="ssh -p $VM_PORT"
    if [[ -n "$VM_KEY" ]]; then
        ssh_cmd="ssh -i $VM_KEY -p $VM_PORT"
    fi
    
    if $ssh_cmd -o ConnectTimeout=10 -o BatchMode=yes "$VM_USER@$VM_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
        log "SSH connection successful"
    else
        error "Cannot connect to VM. Please check your SSH configuration."
        exit 1
    fi
}

# Execute command on remote VM
ssh_execute() {
    local command="$1"
    local ssh_cmd="ssh -p $VM_PORT"
    
    if [[ -n "$VM_KEY" ]]; then
        ssh_cmd="ssh -i $VM_KEY -p $VM_PORT"
    fi
    
    $ssh_cmd "$VM_USER@$VM_HOST" "$command"
}

# Copy files to VM
scp_upload() {
    local local_path="$1"
    local remote_path="$2"
    local scp_cmd="scp -P $VM_PORT"
    
    if [[ -n "$VM_KEY" ]]; then
        scp_cmd="scp -i $VM_KEY -P $VM_PORT"
    fi
    
    $scp_cmd -r "$local_path" "$VM_USER@$VM_HOST:$remote_path"
}

# Copy files from VM
scp_download() {
    local remote_path="$1"
    local local_path="$2"
    local scp_cmd="scp -P $VM_PORT"
    
    if [[ -n "$VM_KEY" ]]; then
        scp_cmd="scp -i $VM_KEY -P $VM_PORT"
    fi
    
    $scp_cmd -r "$VM_USER@$VM_HOST:$remote_path" "$local_path"
}

# Install Blender on VM
install_blender() {
    log "Installing Blender on VM..."
    
    # Check if Blender is already installed (system or snap)
    if ssh_execute "command -v blender" 2>/dev/null; then
        log "Blender is already installed (system)"
        ssh_execute "blender --version" || true
        return 0
    fi
    
    if ssh_execute "snap list blender" 2>/dev/null | grep -q "blender"; then
        log "Blender is already installed (snap)"
        return 0
    fi
    
    # Install based on configured method
    case "${BLENDER_INSTALL_METHOD:-snap}" in
        snap)
            log "Installing Blender via snap..."
            ssh_execute "sudo apt update && sudo snap install blender --classic" || {
                error "Failed to install Blender via snap"
                exit 1
            }
            
            # Enable GPU access for snap Blender - critical for CUDA
            log "Configuring snap Blender for GPU access..."
            ssh_execute "sudo snap connect blender:hardware-observe 2>/dev/null || true"
            ssh_execute "sudo snap connect blender:opengl 2>/dev/null || true"
            ssh_execute "sudo snap connect blender:cuda-control 2>/dev/null || true"
            ssh_execute "sudo snap connect blender:nvidia-driver-support 2>/dev/null || true"
            
            # Check if snap can access NVIDIA GPU
            if ssh_execute "snap run blender --version" 2>/dev/null | grep -q "Blender"; then
                log "Snap Blender installed successfully"
            else
                warning "Snap Blender may have issues. Consider using BLENDER_INSTALL_METHOD=\"official\" for better GPU support"
            fi
            ;;
            
        official)
            log "Installing official Blender build..."
            
            # Download and install official Blender
            ssh_execute "
                cd /tmp &&
                wget -q https://download.blender.org/release/Blender4.0/blender-4.0.2-linux-x64.tar.xz &&
                sudo tar -xf blender-4.0.2-linux-x64.tar.xz -C /opt/ &&
                sudo ln -sf /opt/blender-4.0.2-linux-x64/blender /usr/local/bin/blender &&
                rm blender-4.0.2-linux-x64.tar.xz
            " || {
                error "Failed to install official Blender"
                exit 1
            }
            
            log "Official Blender installed successfully"
            ;;
            
        skip)
            log "Skipping Blender installation (BLENDER_INSTALL_METHOD=skip)"
            if ! ssh_execute "command -v blender" 2>/dev/null; then
                error "Blender not found on VM, but installation was skipped"
                exit 1
            fi
            ;;
            
        *)
            error "Unknown BLENDER_INSTALL_METHOD: ${BLENDER_INSTALL_METHOD}"
            info "Valid options: snap, official, skip"
            exit 1
            ;;
    esac
    
    log "Blender installed successfully"
}

# Prepare remote working directory
prepare_remote_directory() {
    log "Preparing remote working directory..."
    
    ssh_execute "mkdir -p $REMOTE_WORK_DIR/input $REMOTE_WORK_DIR/output" || {
        error "Failed to create remote directories"
        exit 1
    }
    
    log "Remote directories created"
}

# Upload input files
upload_files() {
    if [[ -z "$LOCAL_INPUT_DIR" ]]; then
        warning "No input directory specified, skipping file upload"
        return 0
    fi
    
    if [[ ! -d "$LOCAL_INPUT_DIR" ]]; then
        error "Input directory $LOCAL_INPUT_DIR does not exist"
        exit 1
    fi
    
    log "Uploading files from $LOCAL_INPUT_DIR to VM..."
    
    # Upload the entire directory instead of using glob pattern
    scp_upload "$LOCAL_INPUT_DIR" "$REMOTE_WORK_DIR/" || {
        error "Failed to upload files"
        exit 1
    }
    
    # Upload GPU rendering scripts if GPU rendering is enabled
    if [[ "$USE_GPU_RENDERING" == "true" ]]; then
        log "Uploading GPU rendering scripts..."
        scp_upload "./gpu_render.sh" "$REMOTE_WORK_DIR/" || {
            error "Failed to upload GPU rendering script"
            exit 1
        }
        ssh_execute "chmod +x $REMOTE_WORK_DIR/gpu_render.sh" || {
            error "Failed to make GPU script executable"
            exit 1
        }
    fi
    
    log "Files uploaded successfully"
}

# Run Blender
run_blender() {
    log "Running Blender in background mode..."
    
    # Check if GPU rendering is enabled
    if [[ "$USE_GPU_RENDERING" == "true" ]]; then
        run_gpu_blender
        return $?
    fi
    
    # Validate that we have something to render
    if [[ -z "$BLENDER_FILE" && -z "$BLENDER_SCRIPT" ]]; then
        error "Either BLENDER_FILE or BLENDER_SCRIPT must be specified"
        info "Use -f to specify a .blend file or -s to specify a Python script"
        exit 1
    fi
    
    # Determine which Blender to use based on installation method
    local blender_exec="blender"
    case "${BLENDER_INSTALL_METHOD:-snap}" in
        snap)
            if ssh_execute "snap list blender" 2>/dev/null | grep -q "blender"; then
                blender_exec="snap run blender"
                log "Using snap Blender (as configured)"
            else
                error "Snap Blender not found on VM. Run installation first."
                exit 1
            fi
            ;;
        official)
            if ssh_execute "test -x /opt/blender/blender" 2>/dev/null; then
                blender_exec="/opt/blender/blender"
                log "Using official Blender build from /opt/blender"
            else
                error "Official Blender not found at /opt/blender. Run installation first."
                exit 1
            fi
            ;;
        skip)
            # Use system Blender
            if ssh_execute "command -v blender" 2>/dev/null; then
                blender_exec="blender"
                log "Using pre-installed system Blender"
            else
                error "System Blender not found on VM"
                exit 1
            fi
            ;;
        *)
            error "Unknown BLENDER_INSTALL_METHOD: $BLENDER_INSTALL_METHOD"
            exit 1
            ;;
    esac
    
    local blender_cmd="cd $REMOTE_WORK_DIR && $blender_exec -b"
    
    # Add blend file if specified
    if [[ -n "$BLENDER_FILE" ]]; then
        if [[ "$BLENDER_FILE" == /* ]]; then
            # Absolute path
            blender_cmd="$blender_cmd $BLENDER_FILE"
        else
            # Relative path, assume it's in input directory
            blender_cmd="$blender_cmd input/$BLENDER_FILE"
        fi
    fi
    
    # Add render engine for Cycles (needed for CUDA)
    blender_cmd="$blender_cmd -E CYCLES"
    
    # Add Python script if specified
    if [[ -n "$BLENDER_SCRIPT" ]]; then
        if [[ "$BLENDER_SCRIPT" == /* ]]; then
            # Absolute path
            blender_cmd="$blender_cmd --python $BLENDER_SCRIPT"
        else
            # Relative path, assume it's in input directory
            blender_cmd="$blender_cmd --python input/$BLENDER_SCRIPT"
        fi
    fi
    
    # Add frame range
    blender_cmd="$blender_cmd -s $FRAME_START -e $FRAME_END"
    
    # Add output settings
    blender_cmd="$blender_cmd -o output/render_#### -F $OUTPUT_FORMAT"
    
    # Force CUDA GPU rendering
    blender_cmd="$blender_cmd -- --cycles-device CUDA"
    
    # Add animation flag (only if rendering multiple frames)
    if [[ "$FRAME_END" -gt "$FRAME_START" ]]; then
        blender_cmd="$blender_cmd -a"
    fi
    
    info "Executing: $blender_cmd"
    
    ssh_execute "$blender_cmd" || {
        error "Blender execution failed"
        exit 1
    }
    
    log "Blender execution completed"
}

# Run GPU-optimized Blender rendering
run_gpu_blender() {
    log "Running GPU-optimized Blender rendering..."
    
    # Check if blend file is specified
    if [[ -z "$BLENDER_FILE" ]]; then
        error "GPU rendering requires a .blend file to be specified"
        exit 1
    fi
    
    # Check GPU availability
    log "Checking GPU availability on VM..."
    if ! ssh_execute "nvidia-smi" 2>/dev/null; then
        error "NVIDIA GPUs not detected on VM. GPU rendering requires NVIDIA GPUs."
        exit 1
    fi
    
    # Prepare GPU rendering command
    local blend_path
    if [[ "$BLENDER_FILE" == /* ]]; then
        blend_path="$BLENDER_FILE"
    else
        blend_path="input/$BLENDER_FILE"
    fi
    
    local gpu_cmd="cd $REMOTE_WORK_DIR"
    
    # Add sudo if required
    if [[ "$REQUIRE_SUDO" == "true" ]]; then
        gpu_cmd="$gpu_cmd && sudo ./gpu_render.sh $blend_path $FRAME_START $FRAME_END $GPU_COUNT"
    else
        gpu_cmd="$gpu_cmd && ./gpu_render.sh $blend_path $FRAME_START $FRAME_END $GPU_COUNT"
    fi
    
    info "Executing GPU rendering: $gpu_cmd"
    
    ssh_execute "$gpu_cmd" || {
        error "GPU Blender execution failed"
        exit 1
    }
    
    log "GPU Blender execution completed"
}

# Download output files
download_output() {
    if [[ -z "$LOCAL_OUTPUT_DIR" ]]; then
        warning "No output directory specified, skipping download"
        return 0
    fi
    
    # Create local output directory if it doesn't exist
    mkdir -p "$LOCAL_OUTPUT_DIR"
    
    log "Downloading output files to $LOCAL_OUTPUT_DIR..."
    
    # Check if there are any output files
    if ! ssh_execute "ls $REMOTE_WORK_DIR/output/" 2>/dev/null | grep -q .; then
        warning "No output files found on VM"
        return 0
    fi
    
    scp_download "$REMOTE_WORK_DIR/output/*" "$LOCAL_OUTPUT_DIR/" || {
        error "Failed to download output files"
        exit 1
    }
    
    log "Output files downloaded successfully"
}

# Cleanup remote files
cleanup_remote() {
    if [[ "$CLEANUP_REMOTE" == "true" ]]; then
        log "Cleaning up remote files..."
        ssh_execute "rm -rf $REMOTE_WORK_DIR" || {
            warning "Failed to cleanup remote files"
        }
        log "Remote cleanup completed"
    fi
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -c, --config FILE       Specify configuration file (default: ./config.env)
    -i, --input DIR         Local input directory
    -o, --output DIR        Local output directory
    -f, --file FILE         Blender file to render
    -s, --script FILE       Python script to run in Blender
    -p, --port PORT         SSH port (default: 22)
    --frame-start N         Start frame (default: 1)
    --frame-end N           End frame (default: 1)
    --format FORMAT         Output format (default: png)
    --gpu                   Enable GPU-optimized rendering
    --gpu-count N           Number of GPUs to use (default: 1)
    --require-sudo          GPU configuration requires sudo access
    --test-ssh              Test SSH connection only
    --no-cleanup            Don't cleanup remote files

Examples:
    $0 -i ./input -o ./output -f scene.blend
    $0 -i ./assets -o ./renders -s render_script.py --frame-start 1 --frame-end 100
    $0 -i ./input -o ./output -f animation.blend --gpu --gpu-count 4 --frame-start 1 --frame-end 250
    $0 -i ./input -o ./output -f scene.blend -p 2222  # Custom SSH port
    $0 --test-ssh -p 2222  # Test SSH connection on custom port

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -i|--input)
                LOCAL_INPUT_DIR="$2"
                shift 2
                ;;
            -o|--output)
                LOCAL_OUTPUT_DIR="$2"
                shift 2
                ;;
            -f|--file)
                BLENDER_FILE="$2"
                shift 2
                ;;
            -s|--script)
                BLENDER_SCRIPT="$2"
                shift 2
                ;;
            -p|--port)
                VM_PORT="$2"
                shift 2
                ;;
            --frame-start)
                FRAME_START="$2"
                shift 2
                ;;
            --frame-end)
                FRAME_END="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --gpu)
                USE_GPU_RENDERING=true
                shift
                ;;
            --gpu-count)
                GPU_COUNT="$2"
                shift 2
                ;;
            --require-sudo)
                REQUIRE_SUDO=true
                shift
                ;;
            --test-ssh)
                TEST_SSH_ONLY=true
                shift
                ;;
            --no-cleanup)
                CLEANUP_REMOTE=false
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main execution function
main() {
    log "Starting VM Blender Automation..."
    
    # Load configuration
    load_config
    
    # Test SSH connection
    test_ssh_connection
    
    if [[ "$TEST_SSH_ONLY" == "true" ]]; then
        log "SSH test completed successfully"
        exit 0
    fi
    
    # Execute the workflow
    install_blender
    prepare_remote_directory
    upload_files
    run_blender
    download_output
    cleanup_remote
    
    log "VM Blender Automation completed successfully!"
    
    if [[ -n "$LOCAL_OUTPUT_DIR" ]]; then
        info "Output files are available in: $LOCAL_OUTPUT_DIR"
    fi
}

# Default values for optional flags
TEST_SSH_ONLY=false
CLEANUP_REMOTE=true

# Parse command line arguments
parse_arguments "$@"

# Run main function
main