#!/bin/bash

type zenity &>/dev/null
zenityPresent=$?

type parallel &>/dev/null
parallelPresent=$?

if [ $zenityPresent -ne 0 ]; then
    echo "Zenity must be installed to display UI."
    exit 1
fi

if [ $parallelPresent -ne 0 ]; then
    echo "Parallel must be installed to use multithreading."
    exit 1
fi

path=$(zenity --title="Select the folder containing the videos" --directory --file-selection)

if [[ -z "$path" ]]; then
    echo "No folder selected. Exiting."
    exit 1
fi

mkdir -p "$path/out"

# Loop sui file
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

    ffmpeg -i "$file" -c copy -segment_time 30 -f segment -reset_timestamps 1 "${path}/${filename_noext}"_%04d."$extension"

    if [[ ! -e "${path}/${filename_noext}_0000.$extension" ]]; then
        echo "Error: segmentation failed for $file"
        continue
    fi

    # Webm conversion, handle special chars in files
    parallel -j 8 ffmpeg -i "{}" -c:v libvpx-vp9 -b:v 0 -crf 40 -c:a libopus -ac 2 \
        -threads 16 -row-mt 1 -cpu-used 8 -tile-columns 4 -frame-parallel 1 "{}.webm" ::: "${path}/${filename_noext}"_*."$extension"

    find "$path" -maxdepth 1 -name "${filename_noext}_*.webm" -print0 | sort -zV | awk -v ORS='' '{print "file \x27" $0 "\x27\n"}' > file_list.txt

    ffmpeg -f concat -safe 0 -i file_list.txt -c copy "$path/out/${filename_noext}.webm"

    rm "${path}/${filename_noext}"_*."$extension" "${path}/${filename_noext}"_*.webm file_list.txt
done
