# Vast.ai VM Automation

This script automates the process of selecting, renting, and starting a VM on Vast.ai with Ubuntu template.

## Prerequisites

1. **Vast.ai Account**: Sign up at [vast.ai](https://vast.ai)
2. **API Key**: Get your API key from [cloud.vast.ai/api/](https://cloud.vast.ai/api/)
3. **Optional**: Install `jq` for better JSON parsing: `brew install jq` (macOS)

## Usage

### Basic Usage

```bash
# Set your API key
export VAST_API_KEY="your_api_key_here"

# Run the script
./automate_vast_ai.sh
```

### With Custom Parameters

```bash
# Set environment variables
export VAST_API_KEY="your_api_key_here"
export MAX_PRICE="0.5"        # Maximum $0.50/hour
export MIN_GPU_COUNT="1"      # At least 1 GPU
export UBUNTU_VERSION="22.04" # Ubuntu 22.04

# Run the script
./automate_vast_ai.sh
```

### Help

```bash
./automate_vast_ai.sh --help
```

### Testing and Debugging

```bash
# Test mode (no API calls, uses dummy data)
./automate_vast_ai.sh --test

# Debug mode (shows API responses)
export VAST_API_KEY="your_key"
./automate_vast_ai.sh --debug

# Verbose mode (shows detailed execution)
./automate_vast_ai.sh --verbose

# API diagnostic tool (check what instances are available)
export VAST_API_KEY="your_key"
./diagnose_vast_api.sh
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VAST_API_KEY` | ✅ | - | Your Vast.ai API key |
| `MAX_PRICE` | ❌ | 2.0 | Maximum price per hour (USD) |
| `MIN_GPU_COUNT` | ❌ | 0 | Minimum number of GPUs (0 = CPU-only OK) |
| `UBUNTU_VERSION` | ❌ | 22.04 | Ubuntu version to use |

## Output

The script outputs environment variables that can be consumed by other scripts:

```bash
INSTANCE_ID=12345
SSH_HOST=ssh.vast.ai
SSH_PORT=12345
SSH_USER=root
SSH_COMMAND="ssh -p 12345 root@ssh.vast.ai"
```

## Example Integration

```bash
# Run the automation script and capture output
output=$(./automate_vast_ai.sh 2>/dev/null | grep -E '^(INSTANCE_ID|SSH_HOST|SSH_PORT|SSH_USER|SSH_COMMAND)=')

# Source the output to get variables
eval "$output"

# Use the variables
echo "Connecting to instance $INSTANCE_ID..."
eval "$SSH_COMMAND"
```

### Complete Blender Workflow Example

See `example_blender_workflow.sh` for a complete example that:
1. Provisions a VM
2. Uploads Blender files
3. Runs Blender rendering
4. Downloads results
5. Cleans up the VM

```bash
# Make sure you have your API key set
export VAST_API_KEY="your_api_key"

# Run the complete workflow
./example_blender_workflow.sh
```

## Cleanup

To destroy the instance when done:

```bash
curl -X DELETE "https://cloud.vast.ai/api/v0/instances/$INSTANCE_ID/" \
  -H "Authorization: Bearer $VAST_API_KEY"
```

## Notes

- The script automatically selects the best available instance based on your criteria
- It waits up to 5 minutes for the instance to become ready
- Use `--verbose` flag for detailed debugging output
- The script requires either `jq` for robust JSON parsing or falls back to basic grep parsing

## Troubleshooting

### JSON Parse Errors
If you encounter `jq: parse error: Invalid numeric literal`, this usually means:
1. The API returned an error response instead of valid JSON
2. Use `--debug` flag to see the actual API response
3. Check that your API key is valid and has sufficient permissions

### No Suitable Instances Found
If the script can't find suitable instances:
1. **Run the diagnostic tool first**: `./diagnose_vast_api.sh` to see what's available
2. **Increase `MAX_PRICE`**: Instances might be more expensive than $2.0/hour
   ```bash
   export MAX_PRICE="5.0"  # Allow up to $5/hour
   ```
3. **Allow CPU-only instances**: Set `MIN_GPU_COUNT=0` if GPU isn't required
   ```bash
   export MIN_GPU_COUNT="0"
   ```
4. **Check instance availability**: Vast.ai availability changes frequently

### Connection Issues
- Ensure your API key is valid: get it from [cloud.vast.ai/api/](https://cloud.vast.ai/api/)
- Check your internet connection
- Vast.ai API might be temporarily unavailable

### Testing
Use `--test` flag to verify the script logic without making real API calls:
```bash
./automate_vast_ai.sh --test
```