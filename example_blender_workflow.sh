#!/bin/bash

# Example script showing how to use the Vast.ai automation script output
# This demonstrates how vm_blender_automation.sh could consume the SSH credentials

set -e

echo "Starting Blender automation workflow..."

# Check if automate_vast_ai.sh exists
if [ ! -f "./automate_vast_ai.sh" ]; then
    echo "Error: automate_vast_ai.sh not found in current directory"
    exit 1
fi

# Run the Vast.ai automation and capture the output
echo "Provisioning VM on Vast.ai..."
vm_output=$(./automate_vast_ai.sh 2>/dev/null | grep -E '^(INSTANCE_ID|SSH_HOST|SSH_PORT|SSH_USER|SSH_COMMAND)=')

if [ $? -ne 0 ] || [ -z "$vm_output" ]; then
    echo "Error: Failed to provision VM or capture output"
    exit 1
fi

# Source the output to get variables
eval "$vm_output"

echo "VM provisioned successfully!"
echo "Instance ID: $INSTANCE_ID"
echo "SSH Host: $SSH_HOST"
echo "SSH Port: $SSH_PORT"
echo "SSH User: $SSH_USER"

# Example: Upload files to the VM
echo "Uploading input files..."
scp -P "$SSH_PORT" -o StrictHostKeyChecking=no input/* "$SSH_USER@$SSH_HOST:/tmp/"

# Example: Run Blender on the remote VM
echo "Running Blender automation on remote VM..."
ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no "$SSH_USER@$SSH_HOST" << 'EOF'
    # Install Blender if not already installed
    apt-get update -y
    apt-get install -y blender
    
    # Run Blender on the uploaded file
    cd /tmp
    blender -b ellie_animation.blend -o //output_#### -f 1
    
    # Create output archive
    tar -czf blender_output.tar.gz output_*
EOF

# Example: Download results
echo "Downloading results..."
scp -P "$SSH_PORT" -o StrictHostKeyChecking=no "$SSH_USER@$SSH_HOST:/tmp/blender_output.tar.gz" ./output/

# Cleanup: Destroy the VM
echo "Cleaning up VM..."
if [ -n "$VAST_API_KEY" ] && [ -n "$INSTANCE_ID" ]; then
    curl -s -X DELETE "https://cloud.vast.ai/api/v0/instances/$INSTANCE_ID/" \
        -H "Authorization: Bearer $VAST_API_KEY"
    echo "VM destroyed successfully"
else
    echo "Warning: Could not destroy VM automatically. VAST_API_KEY or INSTANCE_ID not available."
    echo "Manual cleanup required for instance: $INSTANCE_ID"
fi

echo "Blender automation completed!"