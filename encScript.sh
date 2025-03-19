type zenity >> /dev/null
zenityPresent=$?

type parallel >> /dev/null
parallelPresent=$?

if [ $zenityPresent != 0 ]; then

echo "Zenity must be installed in your system to display UI."
exit

elif [ $parallelPresent != 0 ]; then
echo "Parallel must be installed to use multithreading"
exit
fi


path=$(zenity --title="Select the folder containing the videos" --directory --file-selection)

if [[ $? == 1 ]] then
    exit
fi

extensionList=$(zenity --list --text="Select the file extension to convert" --column="ID" --column="Extension" --width=800 --height=600 \
    1   "mp4" \
	2   "mkv" \
	3   "mov" \
	4   "avi" \
	5   "flv" \
	6   "wmv" \
	7   "mpg" \
	8   "mpeg" \
	9   "3gp" \
	10  "ogv" \
	11  "m4v" \
)

if [[ $? == 1 ]] then
    exit
fi

extensions=("mp4" "mkv" "mov" "avi" "flv" "wmv" "mpg" "mpeg" "3gp" "ogv" "m4v")


if [[ $? == 1 ]] then
    exit
fi

for file in "$path"/*."${extensions[$extensionList]}"; do ffmpeg -i "$file" -c copy -segment_time 30 -f segment -reset_timestamps 1 "$file"_%03d."${extensions[$extensionList]}";

parallel -j 8 ffmpeg -i {} -c:v libvpx-vp9 -b:v 0 -crf 40 -c:a libopus \
-threads 16 -row-mt 1 -cpu-used 8 -tile-columns 4 -frame-parallel 1 {.}.webm ::: "$file"_*."${extensions[$extensionList]}";

# List generated webm segments in a file in alphabetical order

ls "$file"_*.webm | sort -V | awk '{print "file \x27" $0 "\x27"}' > file_list.txt;

ffmpeg -f concat -safe 0 -i file_list.txt -c copy "out/$file.webm"

rm "$file"_*."${extensions[$extensionList]}" "$file"_*.webm;
done

cd ..;

done
