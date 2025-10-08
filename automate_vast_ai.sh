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
#   MAX_PRICE       - Optional: Maximum price per hour (default: 1.0)
#   MIN_GPU_COUNT   - Optional: Minimum GPU count (default: 1)
#   UBUNTU_VERSION  - Optional: Ubuntu version (default: 22.04)
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

# Function to search for available instances
search_instances() {
    print_status "Searching for available Ubuntu instances..."
    
    # Test mode with dummy data
    if [ "$TEST_MODE" = "true" ]; then
        echo '[{"id":12345,"rentable":true,"verified":true,"dph_total":0.5,"num_gpus":1}]'
        return
    fi
    
    # Search for available offers (rentable instances) - using simpler endpoint
    local search_result=$(curl -s -X GET \
        "https://cloud.vast.ai/api/v0/bundles/" \
        -H "Authorization: Bearer $VAST_API_KEY" \
        -H "Content-Type: application/json")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to search for instances - curl command failed"
        exit 1
    fi
    
    # Check if we got an error response
    if echo "$search_result" | grep -q '"error"'; then
        print_error "API returned an error:"
        echo "$search_result" | grep -o '"error":"[^"]*"' | cut -d'"' -f4
        exit 1
    fi
    
    # Check if response is empty
    if [ -z "$search_result" ]; then
        print_error "Empty response from API"
        exit 1
    fi
    
    # Debug output to stderr so it doesn't interfere with return value
    if [ "$DEBUG" = "true" ]; then
        print_status "Full API response:"
        echo "$search_result" | head -c 1000 >&2
        echo "" >&2
    fi
    
    echo "$search_result"
}

# Function to find the best instance
find_best_instance() {
    local instances="$1"
    
    print_status "Analyzing available instances..."
    
    # Debug: Show first 200 characters of response
    print_status "API Response preview: $(echo "$instances" | head -c 200)..."
    
    # Check if response is valid JSON
    if command -v jq &> /dev/null; then
        if echo "$instances" | jq empty 2>/dev/null; then
            print_status "Valid JSON response received"
            # Try different possible JSON structures with progressively relaxed criteria
            local instance_id=""
            local criteria_used=""
            
            # Try 1: Strict criteria (verified, rentable, within price/GPU limits)
            if [ -z "$instance_id" ]; then
                instance_id=$(echo "$instances" | jq -r '
                    (.[]?, .offers[]?) | 
                    select(.rentable == true and .verified == true) | 
                    select(.dph_total <= '${MAX_PRICE}') |
                    select(.num_gpus >= '${MIN_GPU_COUNT}') |
                    .id' 2>/dev/null | head -1)
                criteria_used="strict (verified, rentable, price ≤ \$${MAX_PRICE}, GPUs ≥ ${MIN_GPU_COUNT})"
            fi
            
            # Try 2: Remove verification requirement
            if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
                print_warning "No verified instances found, trying unverified..."
                instance_id=$(echo "$instances" | jq -r '
                    (.[]?, .offers[]?) | 
                    select(.rentable == true) | 
                    select(.dph_total <= '${MAX_PRICE}') |
                    select(.num_gpus >= '${MIN_GPU_COUNT}') |
                    .id' 2>/dev/null | head -1)
                criteria_used="relaxed (rentable, price ≤ \$${MAX_PRICE}, GPUs ≥ ${MIN_GPU_COUNT})"
            fi
            
            # Try 3: Increase price limit by 50%
            if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
                local relaxed_price=$(echo "${MAX_PRICE} * 1.5" | bc 2>/dev/null || echo "3.0")
                print_warning "No instances within \$${MAX_PRICE}, trying up to \$${relaxed_price}..."
                instance_id=$(echo "$instances" | jq -r '
                    (.[]?, .offers[]?) | 
                    select(.rentable == true) | 
                    select(.dph_total <= '${relaxed_price}') |
                    select(.num_gpus >= '${MIN_GPU_COUNT}') |
                    .id' 2>/dev/null | head -1)
                criteria_used="price-relaxed (rentable, price ≤ \$${relaxed_price}, GPUs ≥ ${MIN_GPU_COUNT})"
            fi
            
            # Try 4: Remove GPU requirement
            if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
                print_warning "No GPU instances found, trying CPU-only..."
                instance_id=$(echo "$instances" | jq -r '
                    (.[]?, .offers[]?) | 
                    select(.rentable == true) | 
                    select(.dph_total <= '${MAX_PRICE}') |
                    .id' 2>/dev/null | head -1)
                criteria_used="CPU-only (rentable, price ≤ \$${MAX_PRICE})"
            fi
            
            # Try 5: Get cheapest rentable instance regardless of other criteria
            if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
                print_warning "Selecting cheapest available instance..."
                instance_id=$(echo "$instances" | jq -r '
                    (.[]?, .offers[]?) | 
                    select(.rentable == true and .dph_total != null) |
                    sort_by(.dph_total) | .[0].id' 2>/dev/null)
                criteria_used="cheapest available"
            fi
            
            if [ -n "$instance_id" ] && [ "$instance_id" != "null" ]; then
                print_status "Selected instance using: $criteria_used"
            fi
        else
            print_error "Invalid JSON response from API"
            if [ "$DEBUG" = "true" ]; then
                print_error "Raw response: $instances"
            fi
            exit 1
        fi
    else
        # Fallback to basic grep parsing
        print_warning "jq not found, using basic parsing. Install jq for better results."
        local instance_id=$(echo "$instances" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)
    fi
    
    if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
        print_error "No suitable instances found matching criteria:"
        print_error "- Max price: \$${MAX_PRICE}/hour"
        print_error "- Min GPU count: ${MIN_GPU_COUNT}"
        print_error "- Verified and rentable: true"
        
        # Show available instances for debugging
        if command -v jq &> /dev/null; then
            print_error "Available instances:"
            echo "$instances" | jq -r '
                (.[]?, .offers[]?) | 
                select(.id != null) |
                "ID: \(.id), Price: $\(.dph_total // "N/A")/hr, GPUs: \(.num_gpus // 0), Rentable: \(.rentable // false), Verified: \(.verified // false)"
            ' 2>/dev/null | head -5 >&2
        fi
        
        print_error "Available instances preview: $(echo "$instances" | head -c 500)"
        print_error ""
        print_error "Suggestions:"
        print_error "1. Increase MAX_PRICE (try export MAX_PRICE=\"2.0\")"
        print_error "2. Decrease MIN_GPU_COUNT (try export MIN_GPU_COUNT=\"0\")"
        print_error "3. Check if instances are actually rentable"
        exit 1
    fi
    
    echo "$instance_id"
}

# Function to rent an instance
rent_instance() {
    local instance_id="$1"
    
    print_status "Renting instance $instance_id..."
    
    # Test mode
    if [ "$TEST_MODE" = "true" ]; then
        echo "67890"  # Return just the ID, not the JSON
        return
    fi
    
    # Create instance with Ubuntu template
    local rent_result=$(curl -s -X PUT \
        "https://cloud.vast.ai/api/v0/asks/$instance_id/" \
        -H "Authorization: Bearer $VAST_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "client_id": "me",
            "image": "ubuntu:'"$UBUNTU_VERSION"'",
            "args": ["/bin/bash"],
            "env": {},
            "onstart": "echo '\''Instance started at $(date)'\'' > /tmp/startup.log"
        }')
    
    if [ $? -ne 0 ]; then
        print_error "Failed to rent instance"
        exit 1
    fi
    
    # Check if there's an error in the response
    if echo "$rent_result" | grep -q '"error"'; then
        print_error "Error renting instance:"
        echo "$rent_result" | grep -o '"error":"[^"]*"' | cut -d'"' -f4
        exit 1
    fi
    
    # Extract the new instance ID from the response
    if command -v jq &> /dev/null; then
        local new_instance_id=$(echo "$rent_result" | jq -r '.new_contract // empty')
    else
        local new_instance_id=$(echo "$rent_result" | grep -o '"new_contract":[0-9]*' | cut -d':' -f2)
    fi
    
    if [ -z "$new_instance_id" ] || [ "$new_instance_id" = "null" ]; then
        print_error "Failed to get new instance ID from rent response"
        print_error "Response: $rent_result"
        exit 1
    fi
    
    echo "$new_instance_id"
}

# Function to wait for instance to be ready
wait_for_instance() {
    local instance_id="$1"
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    print_status "Waiting for instance $instance_id to be ready..."
    
    # Test mode - simulate ready instance
    if [ "$TEST_MODE" = "true" ]; then
        print_status "Instance is ready! (test mode)"
        return 0
    fi
    
    while [ $wait_time -lt $max_wait ]; do
        local status=$(curl -s -X GET \
            "https://cloud.vast.ai/api/v0/instances/$instance_id" \
            -H "Authorization: Bearer $VAST_API_KEY")
        
        if command -v jq &> /dev/null; then
            local actual_status=$(echo "$status" | jq -r '.instances[0].actual_status // "unknown"')
        else
            local actual_status=$(echo "$status" | grep -o '"actual_status":"[^"]*"' | cut -d'"' -f4)
        fi
        
        case "$actual_status" in
            "running")
                print_status "Instance is ready!"
                return 0
                ;;
            "loading"|"booting")
                print_status "Instance status: $actual_status. Waiting..."
                ;;
            "failed"|"error")
                print_error "Instance failed to start: $actual_status"
                exit 1
                ;;
            *)
                print_status "Instance status: $actual_status. Waiting..."
                ;;
        esac
        
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    print_error "Instance did not become ready within $max_wait seconds"
    exit 1
}

# Function to get SSH connection details
get_ssh_details() {
    local instance_id="$1"
    
    print_status "Getting SSH connection details..."
    
    # Test mode
    if [ "$TEST_MODE" = "true" ]; then
        echo "ssh.vast.ai:22001"
        return
    fi
    
    local instance_info=$(curl -s -X GET \
        "https://cloud.vast.ai/api/v0/instances/$instance_id" \
        -H "Authorization: Bearer $VAST_API_KEY")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get instance information"
        exit 1
    fi
    
    # Extract SSH details
    if command -v jq &> /dev/null; then
        local ssh_host=$(echo "$instance_info" | jq -r '.instances[0].ssh_host // empty')
        local ssh_port=$(echo "$instance_info" | jq -r '.instances[0].ssh_port // empty')
    else
        local ssh_host=$(echo "$instance_info" | grep -o '"ssh_host":"[^"]*"' | cut -d'"' -f4)
        local ssh_port=$(echo "$instance_info" | grep -o '"ssh_port":[0-9]*' | cut -d':' -f2)
    fi
    
    if [ -z "$ssh_host" ] || [ -z "$ssh_port" ] || [ "$ssh_host" = "null" ] || [ "$ssh_port" = "null" ]; then
        print_error "Failed to extract SSH details"
        print_error "Instance info: $instance_info"
        exit 1
    fi
    
    echo "$ssh_host:$ssh_port"
}

# Main execution
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            -d|--debug)
                DEBUG=true
                shift
                ;;
            --test)
                TEST_MODE=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    print_status "Starting Vast.ai VM automation..."
    
    # Check prerequisites
    check_api_key
    
    # Search for instances
    instances=$(search_instances)
    
    # Find best instance
    instance_id=$(find_best_instance "$instances")
    print_status "Selected instance: $instance_id"
    
    # Rent the instance
    rented_instance_id=$(rent_instance "$instance_id")
    print_status "Rented instance ID: $rented_instance_id"
    
    # Wait for instance to be ready
    wait_for_instance "$rented_instance_id"
    
    # Get SSH details
    ssh_details=$(get_ssh_details "$rented_instance_id")
    
    # Output SSH credentials for consumption by other scripts
    echo ""
    echo "# VM Details (can be sourced by other scripts)"
    echo "INSTANCE_ID=$rented_instance_id"
    echo "SSH_HOST=$(echo $ssh_details | cut -d':' -f1)"
    echo "SSH_PORT=$(echo $ssh_details | cut -d':' -f2)"
    echo "SSH_USER=root"
    echo "SSH_COMMAND=\"ssh -p $(echo $ssh_details | cut -d':' -f2) root@$(echo $ssh_details | cut -d':' -f1)\""
    echo ""
    
    print_status "VM is ready! Use the SSH command above to connect."
    print_status "Instance ID: $rented_instance_id"
    print_status "To destroy this instance later, run:"
    print_status "curl -X DELETE \"https://cloud.vast.ai/api/v0/instances/$rented_instance_id/\" -H \"Authorization: Bearer \$VAST_API_KEY\""
}

# Run main function
main "$@"
