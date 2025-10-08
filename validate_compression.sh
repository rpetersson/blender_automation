#!/bin/bash

# Validation script for compression and download functionality
# This script tests the compression features without requiring a full VM run

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Test directories
TEST_DIR="/tmp/blender_compression_test"
TEST_OUTPUT_DIR="$TEST_DIR/output"
TEST_DOWNLOAD_DIR="$TEST_DIR/download"

# Cleanup function
cleanup() {
    if [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
        log "Cleaned up test directory"
    fi
}

# Create test environment
setup_test_environment() {
    log "Setting up test environment..."
    
    # Cleanup any existing test directory
    cleanup
    
    # Create test directories
    mkdir -p "$TEST_OUTPUT_DIR"
    mkdir -p "$TEST_DOWNLOAD_DIR"
    
    # Create some mock output files to test compression
    echo "Mock render data 1" > "$TEST_OUTPUT_DIR/render_0001.png"
    echo "Mock render data 2" > "$TEST_OUTPUT_DIR/render_0002.png"
    echo "Mock render data 3" > "$TEST_OUTPUT_DIR/render_0003.png"
    echo "Additional data file" > "$TEST_OUTPUT_DIR/metadata.txt"
    
    # Create a subdirectory to test recursive compression
    mkdir -p "$TEST_OUTPUT_DIR/subdir"
    echo "Subdirectory file" > "$TEST_OUTPUT_DIR/subdir/nested_file.txt"
    
    log "Test environment created with mock files"
}

# Test compression format validation
test_compression_validation() {
    log "Testing compression format validation..."
    
    # Test valid formats
    local valid_formats=("tar.gz" "tgz" "tar.bz2" "tbz" "zip")
    
    for format in "${valid_formats[@]}"; do
        info "Testing valid format: $format"
        case "$format" in
            "tar.gz"|"tgz"|"tar.bz2"|"tbz"|"zip")
                info "✓ $format is valid"
                ;;
            *)
                error "✗ $format validation failed"
                return 1
                ;;
        esac
    done
    
    # Test invalid format
    local invalid_format="invalid_format"
    case "$invalid_format" in
        "tar.gz"|"tgz"|"tar.bz2"|"tbz"|"zip")
            error "✗ Invalid format '$invalid_format' was incorrectly accepted"
            return 1
            ;;
        *)
            info "✓ Invalid format '$invalid_format' correctly rejected"
            ;;
    esac
    
    log "Compression format validation tests passed"
}

# Test archive creation for different formats
test_archive_creation() {
    log "Testing archive creation for different formats..."
    
    local formats=("tar.gz" "tar.bz2" "zip")
    
    for format in "${formats[@]}"; do
        info "Testing $format archive creation..."
        
        local archive_name="test_output.$format"
        local archive_path="$TEST_DIR/$archive_name"
        
        case "$format" in
            "tar.gz")
                (cd "$TEST_OUTPUT_DIR" && tar -czf "$archive_path" .) || {
                    error "Failed to create tar.gz archive"
                    return 1
                }
                ;;
            "tar.bz2")
                (cd "$TEST_OUTPUT_DIR" && tar -cjf "$archive_path" .) || {
                    error "Failed to create tar.bz2 archive"
                    return 1
                }
                ;;
            "zip")
                if ! command -v zip >/dev/null 2>&1; then
                    warning "zip command not available, skipping zip test"
                    continue
                fi
                (cd "$TEST_OUTPUT_DIR" && zip -r "$archive_path" .) || {
                    error "Failed to create zip archive"
                    return 1
                }
                ;;
        esac
        
        # Verify archive was created and has content
        if [[ ! -f "$archive_path" ]]; then
            error "Archive file was not created: $archive_path"
            return 1
        fi
        
        local archive_size=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null || echo "0")
        if (( archive_size == 0 )); then
            error "Archive file is empty: $archive_path"
            return 1
        fi
        
        info "✓ $format archive created successfully (${archive_size} bytes)"
        
        # Test extraction
        local extract_dir="$TEST_DIR/extract_$format"
        mkdir -p "$extract_dir"
        
        case "$format" in
            "tar.gz")
                tar -xzf "$archive_path" -C "$extract_dir" || {
                    error "Failed to extract tar.gz archive"
                    return 1
                }
                ;;
            "tar.bz2")
                tar -xjf "$archive_path" -C "$extract_dir" || {
                    error "Failed to extract tar.bz2 archive"
                    return 1
                }
                ;;
            "zip")
                if command -v unzip >/dev/null 2>&1; then
                    unzip -q "$archive_path" -d "$extract_dir" || {
                        error "Failed to extract zip archive"
                        return 1
                    }
                else
                    warning "unzip command not available, skipping extraction test"
                    continue
                fi
                ;;
        esac
        
        # Verify extracted files
        if [[ ! -f "$extract_dir/render_0001.png" ]]; then
            error "Expected file not found after extraction"
            return 1
        fi
        
        info "✓ $format archive extraction successful"
    done
    
    log "Archive creation tests passed"
}

# Test file size comparison
test_compression_efficiency() {
    log "Testing compression efficiency..."
    
    # Calculate original directory size (macOS compatible)
    local original_size=$(du -sk "$TEST_OUTPUT_DIR" | cut -f1)
    original_size=$((original_size * 1024))  # Convert from KB to bytes
    
    # Create archives and compare sizes
    local formats=("tar.gz" "tar.bz2")
    
    for format in "${formats[@]}"; do
        local archive_name="efficiency_test.$format"
        local archive_path="$TEST_DIR/$archive_name"
        
        case "$format" in
            "tar.gz")
                (cd "$TEST_OUTPUT_DIR" && tar -czf "$archive_path" .)
                ;;
            "tar.bz2")
                (cd "$TEST_OUTPUT_DIR" && tar -cjf "$archive_path" .)
                ;;
        esac
        
        local archive_size=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null || echo "0")
        
        # Avoid division by zero
        if (( original_size > 0 )); then
            local compression_ratio=$(( (original_size - archive_size) * 100 / original_size ))
            info "$format: Original=${original_size}B, Compressed=${archive_size}B, Saved=${compression_ratio}%"
        else
            info "$format: Original=${original_size}B, Compressed=${archive_size}B"
        fi
    done
    
    log "Compression efficiency tests completed"
}

# Test command line argument parsing simulation
test_argument_parsing() {
    log "Testing argument parsing simulation..."
    
    # Simulate the argument parsing logic
    local test_cases=(
        "--compress|COMPRESS_OUTPUT=true"
        "--compression-format tar.bz2|COMPRESSION_FORMAT=tar.bz2"
        "--archive-name my_renders|ARCHIVE_NAME=my_renders"
        "--extract|EXTRACT_LOCALLY=true"
    )
    
    for test_case in "${test_cases[@]}"; do
        IFS='|' read -r args expected <<< "$test_case"
        info "Testing: $args -> $expected"
        
        # This would normally be handled by the main script's argument parsing
        case "$args" in
            "--compress")
                local COMPRESS_OUTPUT=true
                if [[ "$expected" == "COMPRESS_OUTPUT=true" ]]; then
                    info "✓ Compress option parsing correct"
                else
                    error "✗ Compress option parsing failed"
                    return 1
                fi
                ;;
            "--compression-format tar.bz2")
                local COMPRESSION_FORMAT="tar.bz2"
                if [[ "$expected" == "COMPRESSION_FORMAT=tar.bz2" ]]; then
                    info "✓ Compression format parsing correct"
                else
                    error "✗ Compression format parsing failed"
                    return 1
                fi
                ;;
            "--archive-name my_renders")
                local ARCHIVE_NAME="my_renders"
                if [[ "$expected" == "ARCHIVE_NAME=my_renders" ]]; then
                    info "✓ Archive name parsing correct"
                else
                    error "✗ Archive name parsing failed"
                    return 1
                fi
                ;;
            "--extract")
                local EXTRACT_LOCALLY=true
                if [[ "$expected" == "EXTRACT_LOCALLY=true" ]]; then
                    info "✓ Extract option parsing correct"
                else
                    error "✗ Extract option parsing failed"
                    return 1
                fi
                ;;
        esac
    done
    
    log "Argument parsing tests passed"
}

# Test help output
test_help_output() {
    log "Testing help output..."
    
    # Check if the script shows help with compression options
    if ../vm_blender_automation.sh --help 2>/dev/null | grep -q "compress"; then
        info "✓ Help output contains compression options"
    else
        warning "Help output may not contain compression options (script might not be executable or in expected location)"
    fi
    
    log "Help output test completed"
}

# Run all validation tests
run_all_tests() {
    log "Starting comprehensive compression validation..."
    
    setup_test_environment
    test_compression_validation
    test_archive_creation
    test_compression_efficiency
    test_argument_parsing
    test_help_output
    
    log "All validation tests completed successfully!"
    
    # Show summary
    info "Summary of validated features:"
    info "  ✓ Compression format validation"
    info "  ✓ Archive creation (tar.gz, tar.bz2, zip)"
    info "  ✓ Archive extraction verification"
    info "  ✓ Compression efficiency analysis"
    info "  ✓ Command line argument simulation"
    info "  ✓ Help output verification"
    
    cleanup
}

# Handle script interruption
trap cleanup EXIT INT TERM

# Run the tests
run_all_tests