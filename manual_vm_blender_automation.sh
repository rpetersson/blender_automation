#!/bin/bash

# VM Blender Automation Script
# This script automates the process of:
# 1. SSH into Ubuntu VM
# 2. Install Blender manually from official download
# 3. Upload local files to VM
# 4. Run Blender in background mode
# 5. Download output files back to local machine

set -e  # Exit on any error

# Configuration file path
CONFIG_FILE="./config.env"

# Blender installation settings
BLENDER_VERSION="4.5.3"
BLENDER_DOWNLOAD_URL="https://www.blender.org/download/release/Blender4.5/blender-4.5.3-linux-x64.tar.xz/"
BLENDER_INSTALL_DIR="/opt/blender"
BLENDER_ARCHIVE="blender-${BLENDER_VERSION}-linux-x64.tar.xz"

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
COMPRESS_OUTPUT=true
COMPRESSION_FORMAT="tar.gz"
ARCHIVE_NAME="blender_output"

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
    
    # Validate compression format if compression is enabled
    if [[ "$COMPRESS_OUTPUT" == "true" ]]; then
        case "$COMPRESSION_FORMAT" in
            "tar.gz"|"tgz"|"tar.bz2"|"tbz"|"zip")
                # Valid format
                ;;
            *)
                error "Invalid compression format: $COMPRESSION_FORMAT"
                error "Supported formats: tar.gz, tgz, tar.bz2, tbz, zip"
                exit 1
                ;;
        esac
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
    log "Installing Blender ${BLENDER_VERSION} manually from official download..."

    # Check if Blender is already installed
    if ssh_execute "test -f ${BLENDER_INSTALL_DIR}/blender" 2>/dev/null; then
        local installed_version
        installed_version=$(ssh_execute "${BLENDER_INSTALL_DIR}/blender --version 2>/dev/null | head -1" || echo "")
        
        if echo "$installed_version" | grep -q "$BLENDER_VERSION"; then
            log "Blender ${BLENDER_VERSION} is already installed"
            return 0
        else
            log "Different Blender version found, reinstalling..."
            ssh_execute "rm -rf ${BLENDER_INSTALL_DIR}" 2>/dev/null || true
        fi
    fi

    # Install required dependencies
    log "Installing required dependencies..."
    ssh_execute "apt-get update && apt-get install -y wget xz-utils libxi6 libxxf86vm1 libxfixes3 libxrender1 libgl1" || {
        error "Failed to install dependencies"
        exit 1
    }

    # Download Blender
    log "Downloading Blender ${BLENDER_VERSION}..."
    ssh_execute "cd /tmp && wget -q --show-progress '${BLENDER_DOWNLOAD_URL}' -O '${BLENDER_ARCHIVE}' 2>&1 || wget '${BLENDER_DOWNLOAD_URL}' -O '${BLENDER_ARCHIVE}'" || {
        error "Failed to download Blender from ${BLENDER_DOWNLOAD_URL}"
        exit 1
    }

    # Extract Blender
    log "Extracting Blender archive..."
    ssh_execute "cd /tmp && tar -xf '${BLENDER_ARCHIVE}'" || {
        error "Failed to extract Blender archive"
        exit 1
    }

    # Move to installation directory
    log "Installing Blender to ${BLENDER_INSTALL_DIR}..."
    ssh_execute "mkdir -p $(dirname ${BLENDER_INSTALL_DIR})" || {
        error "Failed to create installation directory"
        exit 1
    }
    
    # Find the extracted directory (it should be blender-4.5.3-linux-x64)
    local extracted_dir="blender-${BLENDER_VERSION}-linux-x64"
    ssh_execute "mv /tmp/${extracted_dir} ${BLENDER_INSTALL_DIR}" || {
        error "Failed to move Blender to installation directory"
        exit 1
    }

    # Clean up downloaded archive
    ssh_execute "rm -f /tmp/${BLENDER_ARCHIVE}" 2>/dev/null || true

    # Create symbolic link for easier access (optional)
    ssh_execute "ln -sf ${BLENDER_INSTALL_DIR}/blender /usr/local/bin/blender" 2>/dev/null || true

    # Verify installation
    if ssh_execute "${BLENDER_INSTALL_DIR}/blender --version" 2>/dev/null | grep -q "Blender ${BLENDER_VERSION}"; then
        log "Blender ${BLENDER_VERSION} installed successfully"
        ssh_execute "${BLENDER_INSTALL_DIR}/blender --version | head -3"
    else
        error "Blender installation verification failed"
        exit 1
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
    
    # Use manually installed Blender
    if ! ssh_execute "test -f ${BLENDER_INSTALL_DIR}/blender" 2>/dev/null; then
        error "Blender not found at ${BLENDER_INSTALL_DIR}/blender. Run installation first."
        exit 1
    fi

    local blender_exec="${BLENDER_INSTALL_DIR}/blender"
    log "Using Blender ${BLENDER_VERSION} from ${BLENDER_INSTALL_DIR}"

    local blend_path
    if [[ "$BLENDER_FILE" == /* ]]; then
        blend_path="$BLENDER_FILE"
    else
        blend_path="input/$BLENDER_FILE"
    fi

    local output_pattern="$REMOTE_WORK_DIR/output/render_####"
    local base_cmd="cd $REMOTE_WORK_DIR && $blender_exec -b '$blend_path' -E CYCLES -o '$output_pattern' -F $OUTPUT_FORMAT"

    # Detect available NVIDIA GPUs (if any)
    local gpu_raw
    gpu_raw=$(ssh_execute "nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null || true") || gpu_raw=""
    local -a gpu_indices=()
    if [[ -n "$gpu_raw" ]]; then
        while IFS= read -r line; do
            local trimmed="${line//[[:space:]]/}"
            if [[ -n "$trimmed" ]]; then
                gpu_indices+=("$trimmed")
            fi
        done <<< "$gpu_raw"
    fi

    local total_frames=$((FRAME_END - FRAME_START + 1))
    if (( total_frames < 1 )); then
        error "Invalid frame range: FRAME_END ($FRAME_END) must be >= FRAME_START ($FRAME_START)"
        exit 1
    fi

    local gpu_count=${#gpu_indices[@]}
    if (( gpu_count > 1 && total_frames > 1 )); then
        log "Detected $gpu_count GPUs; splitting $total_frames frames across them"
        local chunk_size=$(( (total_frames + gpu_count - 1) / gpu_count ))
        local chunk_start=$FRAME_START
        local -a pids=()
        local -a labels=()

        for gpu in "${gpu_indices[@]}"; do
            if (( chunk_start > FRAME_END )); then
                break
            fi

            local range_start=$chunk_start
            local range_end=$((range_start + chunk_size - 1))
            if (( range_end > FRAME_END )); then
                range_end=$FRAME_END
            fi

            local render_cmd="CUDA_VISIBLE_DEVICES=$gpu $base_cmd"
            if (( range_end > range_start )); then
                render_cmd="$render_cmd -s $range_start -e $range_end -a"
            else
                render_cmd="$render_cmd -f $range_start"
            fi
            render_cmd="$render_cmd -- --cycles-device OPTIX"

            info "Launching GPU $gpu: frames $range_start-$range_end"
            ssh_execute "$render_cmd" &
            local pid=$!
            pids+=("$pid")
            labels+=("GPU $gpu (frames $range_start-$range_end)")

            chunk_start=$((range_end + 1))
        done

        local failures=0
        for idx in "${!pids[@]}"; do
            local pid=${pids[$idx]}
            local label=${labels[$idx]}
            if wait "$pid"; then
                log "$label completed"
            else
                error "$label failed"
                failures=$((failures + 1))
            fi
        done

        if (( failures > 0 )); then
            error "One or more GPU renders failed"
            exit 1
        fi

        log "Blender execution completed across $gpu_count GPUs"
        return
    fi

    # Single GPU (or CPU) path
    local render_cmd="$base_cmd"
    if (( total_frames > 1 )); then
        render_cmd="$render_cmd -s $FRAME_START -e $FRAME_END -a"
    else
        render_cmd="$render_cmd -f $FRAME_START"
    fi

    if (( gpu_count >= 1 )); then
        # Pin to the first GPU for consistency
        render_cmd="CUDA_VISIBLE_DEVICES=${gpu_indices[0]} $render_cmd"
        log "Detected GPU ${gpu_indices[0]}; assigning render"
    else
        warning "No NVIDIA GPUs detected via nvidia-smi; falling back to default device"
    fi

    render_cmd="$render_cmd -- --cycles-device OPTIX"

    info "Executing: $render_cmd"

    if ! ssh_execute "$render_cmd"; then
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
    
    # Check if there are any output files
    if ! ssh_execute "ls $REMOTE_WORK_DIR/output/" 2>/dev/null | grep -q .; then
        warning "No output files found on VM"
        return 0
    fi
    
    if [[ "$COMPRESS_OUTPUT" == "true" ]]; then
        download_compressed_output
    else
        download_individual_files
    fi
}

# Download compressed output files
download_compressed_output() {
    log "Compressing and downloading output files..."
    
    # Create archive on remote VM
    local archive_name="${ARCHIVE_NAME}.${COMPRESSION_FORMAT}"
    local remote_archive_path="$REMOTE_WORK_DIR/$archive_name"
    
    case "$COMPRESSION_FORMAT" in
        "tar.gz"|"tgz")
            ssh_execute "cd $REMOTE_WORK_DIR && tar -czf '$archive_name' -C output ." || {
                error "Failed to create tar.gz archive"
                exit 1
            }
            ;;
        "tar.bz2"|"tbz")
            ssh_execute "cd $REMOTE_WORK_DIR && tar -cjf '$archive_name' -C output ." || {
                error "Failed to create tar.bz2 archive"
                exit 1
            }
            ;;
        "zip")
            # Check if zip is available, install if needed
            if ! ssh_execute "which zip" >/dev/null 2>&1; then
                log "Installing zip utility on VM..."
                ssh_execute "apt-get update && apt-get install -y zip" || {
                    error "Failed to install zip utility"
                    exit 1
                }
            fi
            ssh_execute "cd $REMOTE_WORK_DIR/output && zip -r '../$archive_name' ." || {
                error "Failed to create zip archive"
                exit 1
            }
            ;;
        *)
            error "Unsupported compression format: $COMPRESSION_FORMAT"
            error "Supported formats: tar.gz, tgz, tar.bz2, tbz, zip"
            exit 1
            ;;
    esac
    
    # Get archive size for progress indication
    local archive_size
    archive_size=$(ssh_execute "stat -c%s '$remote_archive_path' 2>/dev/null || echo 'unknown'")
    if [[ "$archive_size" != "unknown" ]]; then
        local size_mb=$((archive_size / 1024 / 1024))
        info "Archive created: $archive_name (${size_mb}MB)"
    else
        info "Archive created: $archive_name"
    fi
    
    # Download the compressed archive
    scp_download "$remote_archive_path" "$LOCAL_OUTPUT_DIR/" || {
        error "Failed to download compressed archive"
        exit 1
    }
    
    # Clean up the archive on remote VM
    ssh_execute "rm -f '$remote_archive_path'" 2>/dev/null || {
        warning "Failed to clean up remote archive"
    }
    
    log "Compressed output downloaded successfully to $LOCAL_OUTPUT_DIR/$archive_name"
    
    # Optional: Extract archive locally
    if [[ "$EXTRACT_LOCALLY" == "true" ]]; then
        extract_archive_locally "$LOCAL_OUTPUT_DIR/$archive_name"
    fi
}

# Download individual files (original behavior)
download_individual_files() {
    log "Downloading individual output files to $LOCAL_OUTPUT_DIR..."
    
    scp_download "$REMOTE_WORK_DIR/output/*" "$LOCAL_OUTPUT_DIR/" || {
        error "Failed to download output files"
        exit 1
    }
    
    log "Output files downloaded successfully"
}

# Extract archive locally
extract_archive_locally() {
    local archive_path="$1"
    local extract_dir="${archive_path%.*}"
    
    log "Extracting archive locally to $extract_dir..."
    
    mkdir -p "$extract_dir"
    
    case "$COMPRESSION_FORMAT" in
        "tar.gz"|"tgz")
            tar -xzf "$archive_path" -C "$extract_dir" || {
                error "Failed to extract tar.gz archive"
                return 1
            }
            ;;
        "tar.bz2"|"tbz")
            tar -xjf "$archive_path" -C "$extract_dir" || {
                error "Failed to extract tar.bz2 archive"
                return 1
            }
            ;;
        "zip")
            if ! command -v unzip >/dev/null 2>&1; then
                warning "unzip command not found, skipping local extraction"
                return 1
            fi
            unzip -q "$archive_path" -d "$extract_dir" || {
                error "Failed to extract zip archive"
                return 1
            }
            ;;
    esac
    
    log "Archive extracted to $extract_dir"
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
    --compress              Compress all output files into a single archive
    --compression-format FORMAT  Compression format: tar.gz, tgz, tar.bz2, tbz, zip (default: tar.gz)
    --archive-name NAME     Name for the compressed archive (default: blender_output)
    --extract               Extract compressed archive locally after download
    --test-ssh              Test SSH connection only
    --no-cleanup            Don't cleanup remote files

Examples:
    $0 -i ./input -o ./output -f scene.blend
    $0 -i ./input -o ./output -f animation.blend --frame-start 1 --frame-end 250
    $0 -i ./input -o ./output -f scene.blend --compress --compression-format zip
    $0 -i ./input -o ./output -f animation.blend --compress --extract
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
            --compress)
                COMPRESS_OUTPUT=true
                shift
                ;;
            --compression-format)
                COMPRESSION_FORMAT="$2"
                shift 2
                ;;
            --archive-name)
                ARCHIVE_NAME="$2"
                shift 2
                ;;
            --extract)
                EXTRACT_LOCALLY=true
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
    
    # Show compression status if enabled
    if [[ "$COMPRESS_OUTPUT" == "true" ]]; then
        info "Output compression enabled: $COMPRESSION_FORMAT format"
        info "Archive name: ${ARCHIVE_NAME}.${COMPRESSION_FORMAT}"
        if [[ "$EXTRACT_LOCALLY" == "true" ]]; then
            info "Will extract archive locally after download"
        fi
    fi
    
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
        if [[ "$COMPRESS_OUTPUT" == "true" ]]; then
            info "Compressed output available in: $LOCAL_OUTPUT_DIR/${ARCHIVE_NAME}.${COMPRESSION_FORMAT}"
            if [[ "$EXTRACT_LOCALLY" == "true" ]]; then
                info "Extracted files available in: $LOCAL_OUTPUT_DIR/${ARCHIVE_NAME}"
            fi
        else
            info "Output files are available in: $LOCAL_OUTPUT_DIR"
        fi
    fi
}

# Default values for optional flags
TEST_SSH_ONLY=false
CLEANUP_REMOTE=true
EXTRACT_LOCALLY=false

# Parse command line arguments
parse_arguments "$@"

# Run main function
main