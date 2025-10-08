#!/bin/bash

# Vast.ai VM Automation Script
# This script automatically selects and starts a VM with Ubuntu template and returns SSH credentials
#
# Usage:
#   export VAST_API_KEY="your_api_key_here"
#   ./automate_vast_ai.sh
#
# Environment Variables:
#   VAST_API_KEY    - Required: Your Vast.ai API key
#   MAX_PRICE       - Optional: Maximum price per hour (default: 2.0)
#   MIN_GPU_COUNT   - Optional: Minimum GPU count (default: 0)
#   UBUNTU_VERSION  - Optional: Ubuntu version (default: 22.04)
#   REGION_FILTER   - Optional: Region filter (EU or ANY, default: EU)
#
# Example:
#   export VAST_API_KEY="your_key"
#   export MAX_PRICE="0.5"
#   export MIN_GPU_COUNT="1"
#   ./automate_vast_ai.sh

set -e

# Configuration
VAST_API_KEY="${VAST_API_KEY:-}"
MAX_PRICE="${MAX_PRICE:-2.0}"  # Increased default from 1.0 to 2.0
MIN_GPU_COUNT="${MIN_GPU_COUNT:-0}"  # Changed default from 1 to 0 to include CPU instances
UBUNTU_VERSION="${UBUNTU_VERSION:-22.04}"
REGION_FILTER="${REGION_FILTER:-EU}"
REGION_FILTER=$(echo "$REGION_FILTER" | tr '[:lower:]' '[:upper:]')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to show help
show_help() {
    echo "Vast.ai VM Automation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Environment Variables:"
    echo "  VAST_API_KEY    Required: Your Vast.ai API key"
    echo "  MAX_PRICE       Optional: Maximum price per hour (default: 2.0)"
    echo "  MIN_GPU_COUNT   Optional: Minimum GPU count (default: 0)"
    echo "  UBUNTU_VERSION  Optional: Ubuntu version (default: 22.04)"
    echo "  REGION_FILTER   Optional: Region filter - EU or ANY (default: EU)"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help message"
    echo "  -v, --verbose   Enable verbose output"
    echo "  -d, --debug     Enable debug mode (show API responses)"
    echo "      --test      Test mode (use dummy data, no API calls)"
    echo ""
    echo "Example:"
    echo "  export VAST_API_KEY=\"your_key\""
    echo "  export MAX_PRICE=\"0.5\""
    echo "  export REGION_FILTER=\"EU\""
    echo "  $0"
    echo ""
    echo "Get your API key from: https://cloud.vast.ai/api/"
}

# Check if API key is set
check_api_key() {
    if [ "$TEST_MODE" = "true" ]; then
        print_status "Running in test mode - skipping API key check"
        return
    fi
    
    if [ -z "$VAST_API_KEY" ]; then
        print_error "VAST_API_KEY environment variable is not set"
        print_error "Please set your Vast.ai API key: export VAST_API_KEY='your_api_key_here'"
        print_error "You can get your API key from: https://cloud.vast.ai/api/"
        exit 1
    fi
}
