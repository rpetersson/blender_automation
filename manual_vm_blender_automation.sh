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
# Using latest stable version - update periodically for newer releases
BLENDER_VERSION="4.5.3"
BLENDER_DOWNLOAD_URL="https://download.blender.org/release/Blender4.5/blender-4.5.3-linux-x64.tar.xz"
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

# Progress bar functions
draw_progress_bar() {
    local current=$1
    local total=$2
    local width=$3
    local label=$4
    
    if (( total == 0 )); then
        total=1
    fi
    
    local percent=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))
    
    # Create the bar
    local bar=""
    for ((i = 0; i < filled; i++)); do
        bar="${bar}█"
    done
    for ((i = 0; i < empty; i++)); do
        bar="${bar}░"
    done
    
    printf "${BLUE}%-20s${NC} ${GREEN}%s${NC} ${YELLOW}%3d%%${NC} (%d/%d)\n" "$label" "$bar" "$percent" "$current" "$total"
}

# Parse Blender timing output and extract frame render time
# Input: "Time: 00:18.05 (Saving: 00:00.29)"
# Returns time in seconds (e.g., 18.05)
parse_blender_time() {
    local time_str="$1"
    local minutes=0
    local seconds=0
    
    # Extract MM:SS.SS format
    if [[ "$time_str" =~ ([0-9]+):([0-9]+\.[0-9]+) ]]; then
        minutes="${BASH_REMATCH[1]}"
        seconds="${BASH_REMATCH[2]}"
        # Convert to total seconds
        echo "scale=2; $minutes * 60 + $seconds" | bc 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Track render statistics for a single GPU
# Creates temp files to store frame times and statistics
init_gpu_stats() {
    local gpu_id=$1
    local temp_dir="/tmp/blender_stats_$$"
    mkdir -p "$temp_dir"
    
    # Initialize stats file
    echo "0" > "$temp_dir/gpu_${gpu_id}_frame_count"
    echo "0" > "$temp_dir/gpu_${gpu_id}_total_time"
    echo "0" > "$temp_dir/gpu_${gpu_id}_min_time"
    echo "99999" > "$temp_dir/gpu_${gpu_id}_max_time"
    echo "" > "$temp_dir/gpu_${gpu_id}_times"
    
    echo "$temp_dir"
}

# Update GPU render statistics after each frame
update_gpu_stats() {
    local stats_dir=$1
    local gpu_id=$2
    local frame_number=$3
    local render_time=$4
    
    if [[ ! -d "$stats_dir" ]]; then
        return
    fi
    
    local frame_count_file="$stats_dir/gpu_${gpu_id}_frame_count"
    local total_time_file="$stats_dir/gpu_${gpu_id}_total_time"
    local min_time_file="$stats_dir/gpu_${gpu_id}_min_time"
    local max_time_file="$stats_dir/gpu_${gpu_id}_max_time"
    local times_file="$stats_dir/gpu_${gpu_id}_times"
    
    # Read current values
    local frame_count=$(cat "$frame_count_file" 2>/dev/null || echo "0")
    local total_time=$(cat "$total_time_file" 2>/dev/null || echo "0")
    local min_time=$(cat "$min_time_file" 2>/dev/null || echo "0")
    local max_time=$(cat "$max_time_file" 2>/dev/null || echo "99999")
    
    # Update counters
    frame_count=$((frame_count + 1))
    total_time=$(echo "scale=2; $total_time + $render_time" | bc 2>/dev/null || echo "$total_time")
    
    # Update min/max
    if (( $(echo "$render_time < $min_time" | bc -l 2>/dev/null) )); then
        min_time=$render_time
    fi
    if (( $(echo "$render_time > $max_time" | bc -l 2>/dev/null) )); then
        max_time=$render_time
    fi
    
    # Write back
    echo "$frame_count" > "$frame_count_file"
    echo "$total_time" > "$total_time_file"
    echo "$min_time" > "$min_time_file"
    echo "$max_time" > "$max_time_file"
    echo "$frame_number:$render_time" >> "$times_file"
}

# Get average render time per frame
get_average_frame_time() {
    local stats_dir=$1
    local gpu_id=$2
    
    if [[ ! -d "$stats_dir" ]]; then
        echo "0"
        return
    fi
    
    local frame_count=$(cat "$stats_dir/gpu_${gpu_id}_frame_count" 2>/dev/null || echo "0")
    local total_time=$(cat "$stats_dir/gpu_${gpu_id}_total_time" 2>/dev/null || echo "0")
    
    if (( frame_count > 0 )); then
        echo "scale=2; $total_time / $frame_count" | bc 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Format time string MM:SS.SS from seconds
format_time_from_seconds() {
    local seconds=$1
    local minutes=0
    
    # Handle decimal seconds
    if [[ "$seconds" =~ ^([0-9]+)(\..*)?$ ]]; then
        local int_part="${BASH_REMATCH[1]}"
        minutes=$((int_part / 60))
        seconds=$((int_part % 60))
        printf "%02d:%05.2f" "$minutes" "$seconds"
    else
        echo "00:00.00"
    fi
}

# Calculate ETA based on remaining frames and average time
calculate_eta() {
    local remaining_frames=$1
    local avg_time_per_frame=$2
    
    if (( remaining_frames <= 0 )); then
        echo "0"
        return
    fi
    
    local eta_seconds=$(echo "scale=0; $remaining_frames * $avg_time_per_frame" | bc 2>/dev/null || echo "0")
    echo "$eta_seconds"
}

# Monitor GPU progress and display live progress bars
monitor_gpu_progress() {
    local -a pids=("$@")
    local pid_count=${#pids[@]}
    
    if (( pid_count == 0 )); then
        return 0
    fi
    
    # Store initial frame counts for each GPU
    local -a initial_frames=()
    local -a gpu_labels=()
    local total_all_frames=0
    local completed_all_frames=0
    
    # Parse labels from ssh_execute output
    while IFS= read -r line; do
        if [[ "$line" =~ GPU\ ([0-9]+)\ \(frames\ ([0-9]+)-([0-9]+)\) ]]; then
            local gpu_id="${BASH_REMATCH[1]}"
            local start_frame="${BASH_REMATCH[2]}"
            local end_frame="${BASH_REMATCH[3]}"
            local frame_count=$(( end_frame - start_frame + 1 ))
            
            initial_frames+=("$start_frame:$end_frame:$frame_count")
            gpu_labels+=("GPU $gpu_id")
            total_all_frames=$(( total_all_frames + frame_count ))
        fi
    done
    
    # Monitor processes
    local all_done=false
    local check_interval=5  # Check every 5 seconds
    
    while ! $all_done; do
        all_done=true
        local completed_count=0
        
        # Check if all processes are still running
        for pid in "${pids[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                ((completed_count++))
            else
                all_done=false
            fi
        done
        
        # Clear screen and show header
        clear
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}GPU Render Progress Monitor${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo ""
        
        # Display individual GPU progress bars
        for i in "${!pids[@]}"; do
            draw_progress_bar "$i" "${#pids[@]}" 25 "${gpu_labels[$i]}"
        done
        
        echo ""
        echo -e "${BLUE}───────────────────────────────────────────────────────${NC}"
        
        # Display overall progress
        local overall_percent=$(( pid_count > 0 ? completed_count * 100 / pid_count : 0 ))
        printf "${GREEN}Overall:${NC} %d/%d GPUs completed (${overall_percent}%%)\n" "$completed_count" "$pid_count"
        
        echo ""
        echo -e "${YELLOW}[ESC to background, Ctrl+C to cancel]${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        
        if ! $all_done; then
            sleep "$check_interval"
        fi
    done
    
    # Final status
    echo ""
    echo -e "${GREEN}✓ All GPU renders completed!${NC}"
    echo ""
}

# Enhanced progress indicator with timing statistics
show_render_progress_with_stats() {
    local pid=$1
    local label=$2
    local gpu_id=$3
    local start_frame=$4
    local end_frame=$5
    local stats_dir=$6
    
    local spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
    local idx=0
    local total_frames=$((end_frame - start_frame + 1))
    
    while kill -0 "$pid" 2>/dev/null; do
        local avg_time=$(get_average_frame_time "$stats_dir" "$gpu_id")
        local frames_rendered=$(cat "$stats_dir/gpu_${gpu_id}_frame_count" 2>/dev/null || echo "0")
        local remaining=$((total_frames - frames_rendered))
        local eta_sec=$(calculate_eta "$remaining" "$avg_time")
        local eta_formatted=$(format_time_from_seconds "$eta_sec")
        
        printf "\r${BLUE}${spinner[$idx]}${NC} %s | Frames: %d/%d | Avg: %.2fs | ETA: %s" \
            "$label" "$frames_rendered" "$total_frames" "$avg_time" "$eta_formatted"
        
        idx=$(( (idx + 1) % ${#spinner[@]} ))
        sleep 1
    done
    printf "\r${GREEN}✓${NC} %s - Completed in %.2f seconds\n" "$label" "$(cat "$stats_dir/gpu_${gpu_id}_total_time" 2>/dev/null || echo 0)"
}

# Simple inline progress indicator for single GPU (backward compatible)
show_render_progress() {
    local pid=$1
    local label=$2
    local spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
    local idx=0
    
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${BLUE}${spinner[$idx]}${NC} $label"
        idx=$(( (idx + 1) % ${#spinner[@]} ))
        sleep 0.1
    done
    printf "\r${GREEN}✓${NC} $label completed\n"
}


# Load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Configuration file $CONFIG_FILE not found!"
        info "Please create a config.env file with your VM details."
        info "See config.env.example for reference."
        exit 1
    fi
    
    # Save any variables already set via command line (e.g., --ssh flag)
    local SAVED_VM_HOST="$VM_HOST"
    local SAVED_VM_USER="$VM_USER"
    local SAVED_VM_PORT="$VM_PORT"
    local SAVED_VM_KEY="$VM_KEY"
    
    source "$CONFIG_FILE"
    
    # Restore command-line values if they were set
    [[ -n "$SAVED_VM_HOST" ]] && VM_HOST="$SAVED_VM_HOST"
    [[ -n "$SAVED_VM_USER" ]] && VM_USER="$SAVED_VM_USER"
    [[ -n "$SAVED_VM_PORT" ]] && VM_PORT="$SAVED_VM_PORT"
    [[ -n "$SAVED_VM_KEY" ]] && VM_KEY="$SAVED_VM_KEY"
    
    # Validate required variables
    if [[ -z "$VM_HOST" || -z "$VM_USER" ]]; then
        error "VM_HOST and VM_USER must be set in config.env or via --ssh flag"
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
    
    local ssh_cmd="ssh -p $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    if [[ -n "$VM_KEY" ]]; then
        ssh_cmd="ssh -i $VM_KEY -p $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
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
    local ssh_cmd="ssh -p $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    if [[ -n "$VM_KEY" ]]; then
        ssh_cmd="ssh -i $VM_KEY -p $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    fi
    
    $ssh_cmd "$VM_USER@$VM_HOST" "$command"
}

# Copy files to VM
scp_upload() {
    local local_path="$1"
    local remote_path="$2"
    local scp_cmd="scp -P $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    if [[ -n "$VM_KEY" ]]; then
        scp_cmd="scp -i $VM_KEY -P $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    fi
    
    $scp_cmd -r "$local_path" "$VM_USER@$VM_HOST:$remote_path"
}

# Copy files from VM
scp_download() {
    local remote_path="$1"
    local local_path="$2"
    local scp_cmd="scp -P $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    
    if [[ -n "$VM_KEY" ]]; then
        scp_cmd="scp -i $VM_KEY -P $VM_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
    fi
    
    $scp_cmd -r "$VM_USER@$VM_HOST:$remote_path" "$local_path"
}

# Detect if we need sudo (check if we're root)
setup_sudo() {
    local current_user
    current_user=$(ssh_execute "whoami" 2>/dev/null || echo "")
    
    if [[ "$current_user" == "root" ]]; then
        SUDO_CMD=""
        log "Running as root user, sudo not needed"
    else
        SUDO_CMD="sudo"
        log "Running as non-root user ($current_user), will use sudo for privileged operations"
    fi
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
    ssh_execute "$SUDO_CMD apt-get update && $SUDO_CMD apt-get install -y wget xz-utils libxi6 libxxf86vm1 libxfixes3 libxrender1 libgl1" || {
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
    ssh_execute "$SUDO_CMD mkdir -p $(dirname ${BLENDER_INSTALL_DIR})" || {
        error "Failed to create installation directory"
        exit 1
    }
    
    # Find the extracted directory (it should be blender-4.5.3-linux-x64)
    local extracted_dir="blender-${BLENDER_VERSION}-linux-x64"
    ssh_execute "$SUDO_CMD mv /tmp/${extracted_dir} ${BLENDER_INSTALL_DIR}" || {
        error "Failed to move Blender to installation directory"
        exit 1
    }

    # Clean up downloaded archive
    ssh_execute "rm -f /tmp/${BLENDER_ARCHIVE}" 2>/dev/null || true

    # Create symbolic link for easier access (optional)
    ssh_execute "$SUDO_CMD ln -sf ${BLENDER_INSTALL_DIR}/blender /usr/local/bin/blender" 2>/dev/null || true

    # Verify installation
    local detected_version
    detected_version=$(ssh_execute "${BLENDER_INSTALL_DIR}/blender --version" 2>/dev/null | head -n 1 | grep -oP 'Blender \K[0-9]+\.[0-9]+\.[0-9]+')
    if [[ "$detected_version" == "$BLENDER_VERSION" ]]; then
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
    
    # Use manually installed Blender
    if ! ssh_execute "test -f ${BLENDER_INSTALL_DIR}/blender" 2>/dev/null; then
        error "Blender not found at ${BLENDER_INSTALL_DIR}/blender. Run installation first."
        exit 1
    fi

    local blender_exec="${BLENDER_INSTALL_DIR}/blender"
    log "Using Blender ${BLENDER_VERSION} from ${BLENDER_INSTALL_DIR}"

    # Auto-detect .blend files if BLENDER_FILE is not specified
    local -a blend_files=()
    if [[ -z "$BLENDER_FILE" ]]; then
        log "Auto-detecting .blend files in input directory..."
        local blend_list
        blend_list=$(ssh_execute "find $REMOTE_WORK_DIR/input -maxdepth 2 -type f -name '*.blend' ! -name '*.blend1' 2>/dev/null | sort || true")
        
        if [[ -z "$blend_list" ]]; then
            error "No .blend files found in $REMOTE_WORK_DIR/input"
            info "Please upload .blend files to your input directory or use -f to specify a file"
            exit 1
        fi
        
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                blend_files+=("$line")
            fi
        done <<< "$blend_list"
        
        log "Found ${#blend_files[@]} .blend file(s) to render:"
        for bf in "${blend_files[@]}"; do
            info "  - $(basename "$bf")"
        done
    else
        # Single file specified via -f flag
        local blend_path
        if [[ "$BLENDER_FILE" == /* ]]; then
            blend_path="$BLENDER_FILE"
        else
            blend_path="$REMOTE_WORK_DIR/input/$BLENDER_FILE"
        fi
        blend_files=("$blend_path")
        log "Rendering specified file: $(basename "$blend_path")"
    fi
    
    # Render each .blend file
    local file_count=0
    local total_files=${#blend_files[@]}
    for blend_path in "${blend_files[@]}"; do
        file_count=$((file_count + 1))
        log "═══════════════════════════════════════════════════════════"
        log "Processing file $file_count of $total_files: $(basename "$blend_path")"
        log "═══════════════════════════════════════════════════════════"
        
        # Prompt for frame range for this specific file
        prompt_frame_range_for_file "$(basename "$blend_path")"
        
        render_blend_file "$blend_path" "$blender_exec"
    done
    
    log "All .blend files processed successfully!"
}

# Prompt user for frame range for a specific file
prompt_frame_range_for_file() {
    local filename="$1"
    
    echo ""
    log "Frame Range for: $filename"
    info "Default frame range: ${FRAME_START} to ${FRAME_END}"
    echo ""
    
    # Local variables for this file's frame range
    local file_frame_start=$FRAME_START
    local file_frame_end=$FRAME_END
    
    # Get start frame
    while true; do
        read -p "Enter start frame [$file_frame_start]: " input_start
        # Use default if empty
        if [[ -z "$input_start" ]]; then
            input_start=$file_frame_start
        fi
        # Validate it's a number
        if [[ "$input_start" =~ ^[0-9]+$ ]]; then
            file_frame_start=$input_start
            break
        else
            error "Please enter a valid number"
        fi
    done
    
    # Get end frame
    while true; do
        read -p "Enter end frame [$file_frame_end]: " input_end
        # Use default if empty
        if [[ -z "$input_end" ]]; then
            input_end=$file_frame_end
        fi
        # Validate it's a number and >= start frame
        if [[ "$input_end" =~ ^[0-9]+$ ]]; then
            if (( input_end >= file_frame_start )); then
                file_frame_end=$input_end
                break
            else
                error "End frame must be >= start frame ($file_frame_start)"
            fi
        else
            error "Please enter a valid number"
        fi
    done
    
    local total_frames=$((file_frame_end - file_frame_start + 1))
    echo ""
    info "Will render frames ${file_frame_start} to ${file_frame_end} (${total_frames} frames)"
    
    # Final confirmation
    while true; do
        read -p "Proceed with this file? (y/n): " yn
        case $yn in
            [Yy]* )
                # Update global variables for this file's render
                FRAME_START=$file_frame_start
                FRAME_END=$file_frame_end
                break
                ;;
            [Nn]* )
                warning "Skipping $(basename "$filename")"
                # Set frame range to skip (start > end will be caught)
                FRAME_START=1
                FRAME_END=0
                break
                ;;
            * )
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done
    echo ""
}

# Render a single blend file
render_blend_file() {
    local blend_path="$1"
    local blender_exec="$2"
    local blend_filename=$(basename "$blend_path" .blend)
    
    # Check if user chose to skip this file
    if (( FRAME_END < FRAME_START )); then
        warning "Skipping $blend_filename (user cancelled)"
        return 0
    fi
    
    # Create output subdirectory for this blend file to keep renders organized
    local file_output_dir="$REMOTE_WORK_DIR/output/$blend_filename"
    ssh_execute "mkdir -p '$file_output_dir'" || {
        error "Failed to create output directory for $blend_filename"
        exit 1
    }
    
    local output_pattern="$file_output_dir/frame_####"
    
    log "Output will be saved to: $file_output_dir"
    
    # Build base command without environment variables (added per GPU later)
    local base_cmd="$blender_exec -b '$blend_path' -E CYCLES -o '$output_pattern' -F $OUTPUT_FORMAT"

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

            # Build render command with environment variables for Vulkan fix
            # Use 'env' command to ensure environment variables are set properly over SSH
            local render_cmd="cd $REMOTE_WORK_DIR && env BLENDER_USD_DISABLE_HYDRA=1 CUDA_VISIBLE_DEVICES=$gpu $base_cmd"
            if (( range_end > range_start )); then
                render_cmd="$render_cmd -s $range_start -e $range_end -a"
            else
                render_cmd="$render_cmd -f $range_start"
            fi
            render_cmd="$render_cmd -- --cycles-device OPTIX"

            info "Launching GPU $gpu: frames $range_start-$range_end"
            
            # Initialize stats for this GPU
            local stats_dir=$(init_gpu_stats "$gpu")
            
            # Execute render with output capture
            ssh_execute "$render_cmd" > "/tmp/blender_render_${gpu}_$$.log" 2>&1 &
            local pid=$!
            pids+=("$pid")
            labels+=("GPU $gpu (frames $range_start-$range_end)")
            
            # Store stats directory and frame range for later parsing
            echo "$stats_dir" > "/tmp/gpu_${gpu}_stats_dir_$$"
            echo "$gpu" > "/tmp/gpu_${gpu}_id_$$"
            echo "$range_start" > "/tmp/gpu_${gpu}_start_$$"
            echo "$range_end" > "/tmp/gpu_${gpu}_end_$$"

            chunk_start=$((range_end + 1))
        done

        # Show progress bars while rendering
        echo ""
        info "Rendering on $gpu_count GPUs..."
        echo ""
        
        local failures=0
        
        # Monitor GPU progress with visual feedback and stats
        (
            for idx in "${!pids[@]}"; do
                local pid=${pids[$idx]}
                local label=${labels[$idx]}
                local gpu_id
                gpu_id=$(cat "/tmp/gpu_${idx}_id_$$" 2>/dev/null || echo "$idx")
                local stats_dir
                stats_dir=$(cat "/tmp/gpu_${gpu_id}_stats_dir_$$" 2>/dev/null)
                local range_start
                range_start=$(cat "/tmp/gpu_${gpu_id}_start_$$" 2>/dev/null || echo "0")
                local range_end
                range_end=$(cat "/tmp/gpu_${gpu_id}_end_$$" 2>/dev/null || echo "0")
                
                show_render_progress_with_stats "$pid" "$label" "$gpu_id" "$range_start" "$range_end" "$stats_dir" &
            done
            wait
        )
        
        echo ""
        info "Parsing render timing statistics..."
        
        # Parse timing information from log files
        for gpu in "${gpu_indices[@]}"; do
            if [[ -f "/tmp/blender_render_${gpu}_$$.log" ]]; then
                while IFS= read -r line; do
                    # Look for timing lines like: "Time: 00:18.05 (Saving: 00:00.29)"
                    if [[ "$line" =~ Time:\ ([0-9:\.]+) ]]; then
                        local time_str="${BASH_REMATCH[1]}"
                        local time_sec
                        time_sec=$(parse_blender_time "Time: $time_str")
                        local stats_dir
                        stats_dir=$(cat "/tmp/gpu_${gpu}_stats_dir_$$" 2>/dev/null)
                        if [[ -n "$stats_dir" ]]; then
                            update_gpu_stats "$stats_dir" "$gpu" "0" "$time_sec"
                        fi
                    fi
                done < "/tmp/blender_render_${gpu}_$$.log"
            fi
        done
        
        echo ""
        info "Waiting for all GPU processes to complete..."
        
        # Wait for all processes and collect exit codes
        for idx in "${!pids[@]}"; do
            local pid=${pids[$idx]}
            local label=${labels[$idx]}
            if wait "$pid"; then
                log "✓ $label completed"
            else
                error "✗ $label failed"
                failures=$((failures + 1))
            fi
        done

        if (( failures > 0 )); then
            error "One or more GPU renders failed"
            exit 1
        fi

        # Display render statistics summary
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}Render Statistics${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        
        local total_all_frames=0
        local grand_total_time=0
        
        for gpu in "${gpu_indices[@]}"; do
            local stats_dir
            stats_dir=$(cat "/tmp/gpu_${gpu}_stats_dir_$$" 2>/dev/null)
            if [[ -n "$stats_dir" ]]; then
                local frame_count
                frame_count=$(cat "$stats_dir/gpu_${gpu}_frame_count" 2>/dev/null || echo "0")
                local total_time
                total_time=$(cat "$stats_dir/gpu_${gpu}_total_time" 2>/dev/null || echo "0")
                local avg_time
                avg_time=$(get_average_frame_time "$stats_dir" "$gpu")
                
                printf "${YELLOW}GPU %s:${NC} %d frames | Total: %.2fs | Avg: %.2fs/frame\n" \
                    "$gpu" "$frame_count" "$total_time" "$avg_time"
                
                total_all_frames=$((total_all_frames + frame_count))
                grand_total_time=$(echo "scale=2; $grand_total_time + $total_time" | bc 2>/dev/null || echo "$grand_total_time")
            fi
        done
        
        echo -e "${BLUE}───────────────────────────────────────────────────────${NC}"
        printf "${GREEN}Total:${NC} %d frames | Combined time: %.2fs\n" "$total_all_frames" "$grand_total_time"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo ""
        
        # Cleanup temp files
        for gpu in "${gpu_indices[@]}"; do
            rm -f "/tmp/blender_render_${gpu}_$$.log" 2>/dev/null
            rm -f "/tmp/gpu_${gpu}_stats_dir_$$" 2>/dev/null
            rm -f "/tmp/gpu_${gpu}_id_$$" 2>/dev/null
            rm -f "/tmp/gpu_${gpu}_start_$$" 2>/dev/null
            rm -f "/tmp/gpu_${gpu}_end_$$" 2>/dev/null
        done

        log "Blender execution completed across $gpu_count GPUs"
        return
    fi

    # Single GPU path
    local render_cmd="cd $REMOTE_WORK_DIR && env BLENDER_USD_DISABLE_HYDRA=1 CUDA_VISIBLE_DEVICES=${gpu_indices[0]} $base_cmd"
    if (( total_frames > 1 )); then
        render_cmd="$render_cmd -s $FRAME_START -e $FRAME_END -a"
    else
        render_cmd="$render_cmd -f $FRAME_START"
    fi

    if (( gpu_count >= 1 )); then
        render_cmd="$render_cmd -- --cycles-device OPTIX"
        log "Detected GPU ${gpu_indices[0]}; assigning render with OPTIX"
    else
        error "No NVIDIA GPUs detected via nvidia-smi!"
        error "This script requires GPU rendering. CPU rendering is disabled."
        error "Please use a VM/instance with NVIDIA GPU support."
        exit 1
    fi

    info "Executing: $render_cmd"

    if ! ssh_execute "$render_cmd"; then
        error "Blender render failed for $(basename "$blend_path")"
        error "Check the output above for details"
        exit 1
    fi

    log "Successfully rendered: $(basename "$blend_path")"
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
    -f, --file FILE         Blender file to render (optional - auto-detects all .blend files if not specified)
    --ssh "STRING"          Parse SSH connection string (e.g., "ssh -p 56297 root@157.157.221.29")
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
    # Use SSH connection string from Vast.ai (easiest method)
    $0 --ssh "ssh -p 56297 root@157.157.221.29" -i ./input -o ./output
    
    # Render all .blend files in input directory automatically
    $0 -i ./input -o ./output
    
    # Render all .blend files with frame range
    $0 -i ./input -o ./output --frame-start 1 --frame-end 250
    
    # Render a specific .blend file
    $0 -i ./input -o ./output -f scene.blend
    
    # Render with compression
    $0 -i ./input -o ./output --compress --compression-format zip
    
    # Custom SSH port
    $0 -i ./input -o ./output -p 2222
    $0 --test-ssh -p 2222  # Test SSH connection on custom port

EOF
}

# Parse SSH connection string
parse_ssh_string() {
    local ssh_string="$1"
    
    # Remove leading "ssh" if present
    ssh_string="${ssh_string#ssh }"
    ssh_string="${ssh_string#ssh}"
    ssh_string="${ssh_string## }"  # trim leading spaces
    
    # Extract port if -p flag is present
    if [[ "$ssh_string" =~ -p[[:space:]]+([0-9]+) ]]; then
        VM_PORT="${BASH_REMATCH[1]}"
        # Remove -p PORT from string
        ssh_string=$(echo "$ssh_string" | sed -E 's/-p[[:space:]]+[0-9]+[[:space:]]*//g')
    fi
    
    # Extract -i key if present
    if [[ "$ssh_string" =~ -i[[:space:]]+([^[:space:]]+) ]]; then
        VM_KEY="${BASH_REMATCH[1]}"
        # Remove -i KEY from string
        ssh_string=$(echo "$ssh_string" | sed -E 's/-i[[:space:]]+[^[:space:]]+[[:space:]]*//g')
    fi
    
    # Now parse USER@HOST
    if [[ "$ssh_string" =~ ([^@]+)@([^[:space:]]+) ]]; then
        VM_USER="${BASH_REMATCH[1]}"
        VM_HOST="${BASH_REMATCH[2]}"
    else
        error "Invalid SSH connection string format"
        error "Expected format: 'ssh -p PORT USER@HOST' or 'USER@HOST'"
        error "Example: 'ssh -p 56297 root@157.157.221.29'"
        exit 1
    fi
    
    info "Parsed SSH connection:"
    info "  Host: $VM_HOST"
    info "  User: $VM_USER"
    info "  Port: $VM_PORT"
    if [[ -n "$VM_KEY" ]]; then
        info "  Key: $VM_KEY"
    fi
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
            --ssh)
                # Parse SSH connection string: ssh -p PORT USER@HOST or ssh USER@HOST:PORT
                parse_ssh_string "$2"
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
    
    # Detect if we need sudo
    setup_sudo
    
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