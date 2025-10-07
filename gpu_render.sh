#!/bin/bash
# GPU-Optimized Blender Rendering Script
# Must be run with sudo to configure GPUs
# This script configures NVIDIA GPUs for optimal rendering performance
# and distributes frame rendering across multiple GPUs

# configure the GPU settings to be persistent
nvidia-smi -pm 1
# disable the autoboost feature for all GPUs on the instance
nvidia-smi --auto-boost-default=0
# set all GPU clock speeds to their maximum frequency
nvidia-smi -ac 2505,875

blend_file=$1
start_frame=$2
end_frame=$3
gpu_count=$4
interval=$(( (end_frame-start_frame)/gpu_count ))

echo "Starting GPU-optimized rendering:"
echo "  Blend file: $blend_file"
echo "  Frame range: $start_frame to $end_frame"
echo "  GPU count: $gpu_count"
echo "  Frames per GPU: $interval"

for ((i=0;i<gpu_count;i++))
do
  # Have each gpu render a set of frames
  local_start=$(( start_frame+(i*interval)+i ))
  local_end=$(( local_start + interval ))

  if [ $local_end -gt $end_frame ]; then
    local_end=$end_frame
  fi

  echo "GPU $i rendering frames $local_start to $local_end"

  blender -b $blend_file \
    -noaudio -nojoystick --use-extension 1 \
    -E CYCLES \
    -t 0 \
    -s $local_start \
    -e $local_end \
    -P batch_cycles.py -a -- $i &
done

# Wait for all background processes to complete
wait

echo "GPU rendering completed"