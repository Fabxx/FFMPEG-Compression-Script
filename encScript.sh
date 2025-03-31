#!/bin/bash

# Dependency check
for cmd in zenity parallel; do
    type "$cmd" &>/dev/null || { echo "$cmd must be installed."; exit 1; }
done

# Get all available cores and threads on system
threads=$(nproc --all)
physical_cores=$(lscpu | grep "^Core(s) per socket:" | awk '{print $4}')

path=$(zenity --title="Select the folder containing the videos" --directory --file-selection)

if [[ -z "$path" ]]; then
    echo "No folder selected. Exiting."
    exit 1
fi

cd "$path"

mkdir -p "out"

# For each file that is not webm, create segments of 30 seconds, convert them in webm and then concatenate the segments.
for file in "$path"/*; do
    
    if [[ ! -f "$file" ]]; then
        continue
    fi

    filename=$(basename -- "$file")
    extension="${filename##*.}"
    filename_noext="${filename%.*}"

    # Ignore already converted files
    if [[ "$extension" == "webm" ]]; then
        echo "Skipping $file (already .webm)"
        continue
    fi

    ffmpeg -i "$file" -c copy -segment_time 30 -f segment -reset_timestamps 1 "$path/$filename_noext"_%04d."$extension"

     if [[ ! -e "$path/$filename_noext"_0000."$extension" ]]; then
        echo "Error: segmentation failed for $file"
        continue
    fi

     find . -maxdepth 1 -type f ! -name '*.webm' -print0 | parallel -0 -j $physical_cores --bar \
     ffmpeg -i "{}" -c:v libvpx-vp9 -b:v 0 -crf 40 -c:a libopus -ac 2 \
     -threads $threads -row-mt 1 -cpu-used $physical_cores -tile-columns 4 -frame-parallel 1 "{}.webm" ::: "$path/$filename_noext"_*."$extension"

    # Escape apostrophe char to avoid concat failure when parting file_list.txt
    ls *.webm | sed "s/'/'\\\\''/g" | awk '{print "file \x27" $0 "\x27"}' > file_list.txt

    ffmpeg -f concat -safe 0 -i "file_list.txt" -c copy "out/$filename_noext.webm"

    rm "$filename_noext"_*."$extension" "$filename_noext"_*.webm "file_list.txt"

done
