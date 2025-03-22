#!/bin/bash

# Controllo dipendenze
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

# Selezione cartella
path=$(zenity --title="Select the folder containing the videos" --directory --file-selection)

if [[ -z "$path" ]]; then
    echo "No folder selected. Exiting."
    exit 1
fi

mkdir -p "$path"/out


for file in "$path"/*; do


    if [[ ! -f "$file" ]]; then
        continue
    fi


    filename=$(basename -- "$file")        # Nome del file con estensione
    extension="${filename##*.}"             # Estrai estensione
    filename_noext="${filename%.*}"         # Nome del file senza estensione

    # Segmentazione con ffmpeg mantenendo l'estensione originale
    ffmpeg -i "$file" -c copy -segment_time 30 -f segment -reset_timestamps 1 "${path}/${filename_noext}"_%04d."$extension"

    # Controllo se i segmenti sono stati creati
    if [[ ! -e "${path}/${filename_noext}_0000.$extension" ]]; then
        echo "Error: segmentation failed for $file"
        continue
    fi

    # Conversione con parallel
    parallel -j 8 ffmpeg -i {} -c:v libvpx-vp9 -b:v 0 -crf 40 -c:a libopus \
        -threads 16 -row-mt 1 -cpu-used 8 -tile-columns 4 -frame-parallel 1 {.}.webm ::: "${path}/${filename_noext}"_*."$extension"

    # Creazione file lista
    ls "${path}/${filename_noext}"_*.webm | sort -V | awk '{print "file \x27" $0 "\x27"}' > file_list.txt

    # Unione segmenti WebM
    ffmpeg -f concat -safe 0 -i file_list.txt -c copy "$path/out/${filename_noext}.webm"

    # Pulizia file temporanei
    rm "${path}/${filename_noext}"_*."$extension" "${path}/${filename_noext}"_*.webm file_list.txt

done
