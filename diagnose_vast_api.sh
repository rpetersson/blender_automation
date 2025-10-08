#!/bin/bash

# Vast.ai API Diagnostic Script
# This script helps diagnose issues with the Vast.ai API

echo "Vast.ai API Diagnostic Tool"
echo "=========================="

if [ -z "$VAST_API_KEY" ]; then
    echo "❌ VAST_API_KEY not set"
    echo "   Please set: export VAST_API_KEY='your_api_key'"
    echo "   Get your key from: https://cloud.vast.ai/api/"
    exit 1
else
    echo "✅ VAST_API_KEY is set"
fi

echo ""
echo "Testing API connectivity..."

# Test basic API connectivity
response=$(curl -s -w "%{http_code}" -o /tmp/vast_response.json \
    "https://cloud.vast.ai/api/v0/bundles/" \
    -H "Authorization: Bearer $VAST_API_KEY" \
    -H "Content-Type: application/json")

http_code="${response: -3}"
echo "HTTP Status Code: $http_code"

if [ "$http_code" = "200" ]; then
    echo "✅ API request successful"
    
    # Check if jq is available
    if command -v jq &> /dev/null; then
        echo ""
        echo "Analyzing response with jq..."
        
        # Count total offers
        total_offers=$(jq '.offers | length' /tmp/vast_response.json 2>/dev/null || echo "0")
        echo "Total offers found: $total_offers"
        
        # Count rentable offers
        rentable_offers=$(jq '[.offers[] | select(.rentable == true)] | length' /tmp/vast_response.json 2>/dev/null || echo "0")
        echo "Rentable offers: $rentable_offers"
        
        # Show price range
        if [ "$rentable_offers" -gt 0 ]; then
            min_price=$(jq '[.offers[] | select(.rentable == true and .dph_total != null) | .dph_total] | min' /tmp/vast_response.json 2>/dev/null || echo "N/A")
            max_price=$(jq '[.offers[] | select(.rentable == true and .dph_total != null) | .dph_total] | max' /tmp/vast_response.json 2>/dev/null || echo "N/A")
            echo "Price range: $${min_price} - $${max_price} per hour"
            
            echo ""
            echo "Top 5 cheapest rentable instances:"
            jq -r '.offers[] | select(.rentable == true and .dph_total != null) | 
                   "\(.id): $\(.dph_total)/hr, \(.num_gpus // 0) GPUs, \(.cpu_cores // 0) CPUs, \(.cpu_ram // 0)MB RAM"' \
                   /tmp/vast_response.json 2>/dev/null | sort -k2 -n | head -5
        fi
        
    else
        echo "⚠️  jq not found - install with: brew install jq (macOS) or apt install jq (Ubuntu)"
        echo ""
        echo "Raw response preview:"
        head -c 500 /tmp/vast_response.json
    fi
    
elif [ "$http_code" = "401" ]; then
    echo "❌ Authentication failed - check your API key"
elif [ "$http_code" = "403" ]; then
    echo "❌ Access forbidden - API key may not have sufficient permissions"
else
    echo "❌ API request failed"
    echo "Response:"
    cat /tmp/vast_response.json
fi

# Cleanup
rm -f /tmp/vast_response.json

echo ""
echo "Suggested actions:"
echo "1. If auth fails: Get a new API key from https://cloud.vast.ai/api/"
echo "2. If no rentable instances: Try increasing MAX_PRICE"
echo "3. If prices too high: Consider using CPU-only instances (MIN_GPU_COUNT=0)"