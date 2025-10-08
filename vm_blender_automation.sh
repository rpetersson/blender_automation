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
OUTPUT_FORMAT="png"
FRAME_START=1
FRAME_END=1

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
    log "Ensuring Blender (snap) is installed on VM..."

    if ssh_execute "snap list blender" 2>/dev/null | grep -q "blender"; then
        log "Snap Blender already installed"
        return 0
    fi

    log "Installing Blender via snap..."
    ssh_execute "sudo apt update && sudo snap install blender --classic" || {
        error "Failed to install Blender via snap"
        exit 1
    }

    # Enable GPU access for snap Blender - critical for GPU rendering
    log "Configuring snap Blender for GPU access..."
    ssh_execute "sudo snap connect blender:hardware-observe 2>/dev/null || true"
    ssh_execute "sudo snap connect blender:opengl 2>/dev/null || true"
    ssh_execute "sudo snap connect blender:cuda-control 2>/dev/null || true"
    ssh_execute "sudo snap connect blender:nvidia-driver-support 2>/dev/null || true"

    if ssh_execute "snap run blender --version" 2>/dev/null | grep -q "Blender"; then
        log "Snap Blender installed successfully"
    else
        warning "Snap Blender installation completed but version check failed"
    fi
}

# Prepare remote working directory
prepare_remote_directory() {
    log "Preparing remote working directory..."
    
    # Clean up any existing work directory to prevent memory leaks
    log "Cleaning up previous work directory..."
    ssh_execute "rm -rf $REMOTE_WORK_DIR" 2>/dev/null || true
    
    # Create fresh directories
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
    
    log "Files uploaded successfully"
}

# Run Blender
run_blender() {
    log "Running Blender in background mode..."
    
    # Validate that we have a blend file to render
    if [[ -z "$BLENDER_FILE" ]]; then
        error "BLENDER_FILE must be specified"
        info "Use -f to specify a .blend file"
        exit 1
    fi
    
    # Always use snap Blender
    if ! ssh_execute "snap list blender" 2>/dev/null | grep -q "blender"; then
        error "Snap Blender not found on VM. Run installation first."
        exit 1
    fi

    local blender_exec="snap run blender"
    log "Using snap Blender"
    
    local blender_cmd="cd $REMOTE_WORK_DIR && $blender_exec -b"
    
    # Add blend file (required)
    if [[ "$BLENDER_FILE" == /* ]]; then
        # Absolute path
        blender_cmd="$blender_cmd $BLENDER_FILE"
    else
        # Relative path, assume it's in input directory
        blender_cmd="$blender_cmd input/$BLENDER_FILE"
    fi
    
    # Add render engine for Cycles (needed for CUDA)
    blender_cmd="$blender_cmd -E CYCLES"
    
    # Add output settings (use absolute path so Blender writes where we expect)
    local output_pattern="$REMOTE_WORK_DIR/output/render_####"
    blender_cmd="$blender_cmd -o '$output_pattern' -F $OUTPUT_FORMAT"

    # Add frame parameters (place after output so Blender uses the pattern when rendering)
    if [[ "$FRAME_END" -gt "$FRAME_START" ]]; then
        blender_cmd="$blender_cmd -s $FRAME_START -e $FRAME_END -a"
    else
        blender_cmd="$blender_cmd -f $FRAME_START"
    fi

    # Force OPTIX GPU rendering
    blender_cmd="$blender_cmd -- --cycles-device OPTIX"
    
    info "Executing: $blender_cmd"
    
    # Execute and capture output
    if ! ssh_execute "$blender_cmd"; then
        error "Blender execution failed"
        error "Check the output above for details"
        exit 1
    fi
    
    log "Blender execution completed"
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
    -p, --port PORT         SSH port (default: 22)
    --frame-start N         Start frame (default: 1)
    --frame-end N           End frame (default: 1)
    --format FORMAT         Output format (default: png)
    --test-ssh              Test SSH connection only
    --no-cleanup            Don't cleanup remote files

Examples:
    $0 -i ./input -o ./output -f scene.blend
    $0 -i ./input -o ./output -f animation.blend --frame-start 1 --frame-end 250
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