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
    
    # Search for available offers (rentable instances) - using correct endpoint
    if [ "$DEBUG" = "true" ]; then
        print_status "Making API request to: https://console.vast.ai/api/v0/bundles/"
        print_status "Using Authorization header with API key: ${VAST_API_KEY:0:10}..."
    fi
    
    local search_result=$(curl -s -w "HTTP_CODE:%{http_code}" \
        "https://console.vast.ai/api/v0/bundles/" \
        -H "Authorization: Bearer $VAST_API_KEY" \
        -H "Content-Type: application/json")
    
    # Extract HTTP code and response
    local http_code=$(echo "$search_result" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    local json_response=$(echo "$search_result" | sed 's/HTTP_CODE:[0-9]*$//')
    
    if [ "$DEBUG" = "true" ]; then
        print_status "HTTP Status Code: $http_code"
        print_status "Response length: $(echo "$json_response" | wc -c) characters"
    fi
    
    if [ $? -ne 0 ]; then
        print_error "Failed to search for instances - curl command failed"
        exit 1
    fi
    
    # Check HTTP status code
    if [ "$http_code" != "200" ]; then
        print_error "HTTP request failed with status code: $http_code"
        case $http_code in
            401) print_error "Authentication failed - check your API key" ;;
            403) print_error "Access forbidden - API key may not have permissions" ;;
            404) print_error "API endpoint not found - may have changed" ;;
            429) print_error "Rate limit exceeded - wait and try again" ;;
            500) print_error "Server error - Vast.ai API may be down" ;;
            *) print_error "Unknown HTTP error" ;;
        esac
        print_error "Response: $json_response"
        exit 1
    fi
    
    search_result="$json_response"
    
    # Check if we got an error response
    if echo "$search_result" | grep -q '"error"'; then
        print_error "API returned an error:"
        local error_msg=$(echo "$search_result" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        print_error "$error_msg"
        if [ "$DEBUG" = "true" ]; then
            print_error "Full response: $search_result"
        fi
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
            
            # Try 1: Just get the first instance with an ID (simplest possible)
            if [ -z "$instance_id" ]; then
                instance_id=$(echo "$instances" | jq -r '.offers[0].id' 2>/dev/null)
                criteria_used="first available instance"
            fi
            
            # Try 2: Remove verification requirement
            if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
                print_warning "No verified instances found, trying unverified..."
                instance_id=$(echo "$instances" | jq -r '
                    (.[]?, .offers[]?) | 
                    select(.rented == null) | 
                    select(.dph_total <= '${MAX_PRICE}') |
                    select(.num_gpus >= '${MIN_GPU_COUNT}') |
                    .id' 2>/dev/null | head -1)
                criteria_used="relaxed (not rented, price ≤ \$${MAX_PRICE}, GPUs ≥ ${MIN_GPU_COUNT})"
            fi
            
            # Try 3: Increase price limit by 50%
            if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
                local relaxed_price=$(echo "${MAX_PRICE} * 1.5" | bc 2>/dev/null || echo "3.0")
                print_warning "No instances within \$${MAX_PRICE}, trying up to \$${relaxed_price}..."
                instance_id=$(echo "$instances" | jq -r '
                    (.[]?, .offers[]?) | 
                    select(.rented == null) | 
                    select(.dph_total <= '${relaxed_price}') |
                    select(.num_gpus >= '${MIN_GPU_COUNT}') |
                    .id' 2>/dev/null | head -1)
                criteria_used="price-relaxed (not rented, price ≤ \$${relaxed_price}, GPUs ≥ ${MIN_GPU_COUNT})"
            fi
            
            # Try 4: Remove GPU requirement
            if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
                print_warning "No GPU instances found, trying CPU-only..."
                instance_id=$(echo "$instances" | jq -r '
                    (.[]?, .offers[]?) | 
                    select(.rented == null) | 
                    select(.dph_total <= '${MAX_PRICE}') |
                    .id' 2>/dev/null | head -1)
                criteria_used="CPU-only (not rented, price ≤ \$${MAX_PRICE})"
            fi
            
            # Try 5: Get cheapest available instance regardless of other criteria
            if [ -z "$instance_id" ] || [ "$instance_id" = "null" ]; then
                print_warning "Selecting cheapest available instance..."
                instance_id=$(echo "$instances" | jq -r '
                    (.[]?, .offers[]?) | 
                    select(.rented == null and .dph_total != null) |
                    sort_by(.dph_total) | .[0].id' 2>/dev/null)
                criteria_used="cheapest available (not rented)"
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
            print_error "First instance details:"
            echo "$instances" | jq -r '.offers[0] | 
                "ID: \(.id // "N/A")",
                "Price: $\(.dph_total // "N/A")/hr", 
                "Rentable field exists: \(has("rentable"))",
                "Rentable value: \(.rentable // "null")",
                "Rented field exists: \(has("rented"))",
                "Rented value: \(.rented // "null")",
                "Verification: \(.verification // "N/A")",
                "GPUs: \(.num_gpus // "N/A")"
            ' 2>/dev/null | head -10 >&2
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
        return 0
    fi
    
    # Create instance with Ubuntu template
    local rent_result=$(curl -s -X PUT \
        "https://console.vast.ai/api/v0/asks/$instance_id/" \
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
        print_error "Failed to rent instance (curl error)"
        return 1
    fi
    
    # Check if there's an error in the response
    if echo "$rent_result" | grep -q '"error"'; then
        local error_msg=$(echo "$rent_result" | grep -o '"error":"[^"]*"' | cut -d'"' -f4)
        print_warning "Error renting instance $instance_id: $error_msg"
        if [ "$DEBUG" = "true" ]; then
            print_error "Full rent response: $rent_result"
        fi
        return 1
    fi
    
    # Extract the new instance ID from the response
    if command -v jq &> /dev/null; then
        local new_instance_id=$(echo "$rent_result" | jq -r '.new_contract // empty')
    else
        local new_instance_id=$(echo "$rent_result" | grep -o '"new_contract":[0-9]*' | cut -d':' -f2)
    fi
    
    if [ -z "$new_instance_id" ] || [ "$new_instance_id" = "null" ]; then
        print_warning "Failed to get new instance ID from rent response for instance $instance_id"
        if [ "$DEBUG" = "true" ]; then
            print_error "Response: $rent_result"
        fi
        return 1
    fi
    
    print_status "Successfully rented instance $instance_id -> $new_instance_id"
    
    echo "$new_instance_id"
    return 0
}

# Function to get multiple instance IDs to try
get_available_instances() {
    local instances="$1"
    
    print_status "Getting list of instances to try..."
    
    # Check if response is valid JSON
    if command -v jq &> /dev/null; then
        if echo "$instances" | jq empty 2>/dev/null; then
            # Get up to 5 instance IDs to try, in order of preference
            local instance_ids=$(echo "$instances" | jq -r '
                .offers[] | 
                select(.rentable == true) |
                select(.rented == null or .rented == false) |
                select(.dph_total <= '${MAX_PRICE}') |
                .id' 2>/dev/null | head -5)
            
            if [ -z "$instance_ids" ]; then
                print_warning "No instances found with strict criteria, trying relaxed..."
                # Relaxed criteria - just get rentable instances
                instance_ids=$(echo "$instances" | jq -r '
                    .offers[] | 
                    select(.rentable == true) |
                    .id' 2>/dev/null | head -5)
            fi
            
            if [ -z "$instance_ids" ]; then
                print_warning "No rentable instances found, trying any instances..."
                # Very relaxed - any instance with an ID
                instance_ids=$(echo "$instances" | jq -r '.offers[].id' 2>/dev/null | head -5)
            fi
            
            if [ -n "$instance_ids" ]; then
                echo "$instance_ids"
                return 0
            fi
        else
            print_error "Invalid JSON response"
            return 1
        fi
    else
        print_warning "jq not available, using grep to find instance ID"
        # Fallback method without jq
        local instance_ids=$(echo "$instances" | grep -o '"id":[0-9]*' | head -5 | cut -d':' -f2)
        if [ -n "$instance_ids" ]; then
            echo "$instance_ids"
            return 0
        fi
    fi
    
    print_error "No suitable instances found"
    return 1
}

# Function to find and rent the best available instance
find_and_rent_instance() {
    local instances="$1"
    local instance_ids
    
    instance_ids=$(get_available_instances "$instances")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    print_status "Found $(echo "$instance_ids" | wc -l | tr -d ' ') instances to try"
    
    # Try each instance until one works
    while IFS= read -r instance_id; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "null" ]; then
            print_status "Attempting to rent instance: $instance_id"
            
            # Capture the output (new instance ID) and check return code
            local rent_output
            rent_output=$(rent_instance "$instance_id")
            local rent_result=$?
            
            if [ $rent_result -eq 0 ] && [ -n "$rent_output" ]; then
                print_status "Successfully rented instance $instance_id -> $rent_output"
                echo "$rent_output"
                return 0
            else
                print_warning "Instance $instance_id failed to rent, trying next..."
            fi
        fi
    done <<< "$instance_ids"
    
    print_error "All available instances failed to rent"
    return 1
}

# Function to start an instance
start_instance() {
    local instance_id="$1"
    
    print_status "Starting instance $instance_id..."
    
    # Test mode
    if [ "$TEST_MODE" = "true" ]; then
        print_status "Instance start command sent successfully (test mode)"
        return 0
    fi
    
    local start_result=$(curl -s -X PUT \
        "https://console.vast.ai/api/v0/instances/$instance_id/" \
        -H "Authorization: Bearer $VAST_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"state": "running"}')
    
    if echo "$start_result" | grep -q '"success":true'; then
        print_status "Instance start command sent successfully"
        return 0
    else
        print_warning "Failed to send start command"
        if [ "$DEBUG" = "true" ]; then
            print_error "Start response: $start_result"
        fi
        return 1
    fi
}

# Function to wait for instance to be ready
wait_for_instance() {
    local instance_id="$1"
    local max_wait=600  # 10 minutes
    local wait_time=0
    local instance_started=false
    
    print_status "Waiting for instance $instance_id to be ready..."
    
    # Test mode - simulate ready instance
    if [ "$TEST_MODE" = "true" ]; then
        print_status "Instance is ready! (test mode)"
        return 0
    fi
    
    while [ $wait_time -lt $max_wait ]; do
        local status=$(curl -s -X GET \
            "https://console.vast.ai/api/v0/instances/$instance_id/" \
            -H "Authorization: Bearer $VAST_API_KEY")
        
        if command -v jq &> /dev/null; then
            local actual_status=$(echo "$status" | jq -r '.instances.actual_status // "unknown"')
        else
            local actual_status=$(echo "$status" | grep -o '"actual_status":"[^"]*"' | cut -d'"' -f4)
        fi
        
        case "$actual_status" in
            "running")
                print_status "Instance is ready!"
                return 0
                ;;
            "created")
                if [ "$instance_started" = false ]; then
                    print_status "Instance created, starting it..."
                    if start_instance "$instance_id"; then
                        instance_started=true
                        print_status "Start command sent, waiting for instance to load..."
                    else
                        print_error "Failed to start instance"
                        exit 1
                    fi
                else
                    print_status "Instance status: $actual_status. Waiting for it to start loading..."
                fi
                ;;
            "loading"|"booting")
                instance_started=true  # If we see loading, the start command worked
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
        "https://console.vast.ai/api/v0/instances/$instance_id/" \
        -H "Authorization: Bearer $VAST_API_KEY")
    
    if [ $? -ne 0 ]; then
        print_error "Failed to get instance information"
        exit 1
    fi
    
    # Extract SSH details
    if command -v jq &> /dev/null; then
        local ssh_host=$(echo "$instance_info" | jq -r '.instances.ssh_host // empty')
        local ssh_port=$(echo "$instance_info" | jq -r '.instances.ssh_port // empty')
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
    
    # Find and rent the best available instance
    print_status "Searching for and renting an available instance..."
    rented_instance_id=$(find_and_rent_instance "$instances")
    if [ $? -ne 0 ]; then
        print_error "Failed to rent any available instance"
        exit 1
    fi
    print_status "Successfully rented instance ID: $rented_instance_id"
    
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
    print_status "curl -X DELETE \"https://console.vast.ai/api/v0/instances/$rented_instance_id/\" -H \"Authorization: Bearer \$VAST_API_KEY\""
}

# Run main function
main "$@"
