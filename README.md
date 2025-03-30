# Dependencies
- parallel (linux)
- zenity for UI

# Behavior

- Get original video source and create segments of `30` seconds each without re-encoding
  
- Executes parallel compression with available physical core with the following syntax:
  - `parallel -j x`     where `x` is the number of physical cores
  - `-c:v encoder`      name of the encoder used, in this case `libvpx-vp9`
  - `-b:v 0`            disables fixed bitrate
  - `-cfr 40`           high compression rate, visually the qualty feels lossless.
  - `-c:a libopus`      for efficient audio encoding
  - `-threads x`        available threads in total.
  - `-row-mt 1`         enables multi-threading for VP9.
  - `-cpu-used x`       optimized speed encoding, x are physical cores.
  - `-tile-columns 4`   divides the video in columns to optimize parallel encoding.
  - `-frame-parallel 1` enables parallel encoding of frames.
  
- Concatenates the generated webm segments into a final `webm` video file.

NOTE: Cores and threads are automatically obtained. Special characters are handled.

# Test results

- source: `mp4 h264 1920x1080 50FPS 2.5gb`
- destination: `webm VP9 800mb`

# NOTE
Results may vary based on the original compression of the file, might compress more, or less.
