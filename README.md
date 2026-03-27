# mpv-seekpeek

A YouTube-style thumbnail preview on seekbar hover for mpv.  
A lightweight Lua script that generates and displays video previews using FFmpeg sprite sheets.

<p align="center">
    <img alt="mpv-seekpeek demo" src="https://github.com/user-attachments/assets/66d135e4-bb28-4fc2-bf17-a9d1b5122964" width="720"/>
</p>

<br>

## 📦 Prerequisites

- **[mpv](https://mpv.io/)**: media player
- **[FFmpeg](https://ffmpeg.org/)**: used to generate thumbnail sprite sheets

Make sure both are installed and available in your `PATH` (this would be added in Unix automatically).

<br>

## ⚙️ Installation

### ☀️ Using Git (recommended)

Clone the repository to the `mpv/scripts` directory.
The command below works on the GNU operating system with `git` installed.

```bash
git clone https://github.com/soorajsprakash/mpv-seekpeek ~/.config/mpv/scripts/mpv-seekpeek
```

To update the script in the future, go to the mpv-seekpeek directory and pull the latest changes:

```bash
cd ~/.config/mpv/scripts/mpv-seekpeek && git pull
```

### 📁 Manual

Download the files and place them in the appropriate mpv scripts directory as per your OS:

| OS        | Location                 |
| --------- | ------------------------ |
| GNU/Linux | `~/.config/mpv/scripts/` |

Both `main.lua` and `helper.lua` must be present inside the folder.

<br>

## ▶️ Usage

1. Install the script
2. Open any video in mpv.
3. The script automatically begins generating a thumbnail sprite sheet in the background when playback starts.
4. Once the sprite sheet is generated, an on-screen message will notify you (might take some time for older CPUs).
5. From that point, hover your cursor over the seekbar to see thumbnail previews.

> Generated sprite sheets are stored in mpv's cache directory.

<br>

## 🧠 How It Works

This script replicates the same technique used by platforms like YouTube and Netflix for seekbar previews.

**The sprite sheet approach**

Instead of decoding individual frames on demand (which is slow and resource heavy), a single (or multi) **sprite sheet** is generated once upfront. When the user hovers over the seekbar, the script calculates which cell in the grid corresponds to that timestamp and renders only that portion.

YouTube's storyboard system works identically: the player fetches a pre-generated sprite grid and uses coordinate offsets to display the right thumbnail.

🔱 **Pipeline**

1. **Async generation**:  On playback start, FFmpeg is invoked as a non-blocking subprocess so video playback is never stalled:
   ```
   fps=1/5 -> scale=240:100 -> tile=30x30 -> format=bgra -> rawvideo output
   ```
   One frame is sampled every 5 seconds, scaled, and tiled into a 30x30 grid written as a raw BGRA binary file.
   > Generating sprite as bgra because mpv only supports bgra for showing overlays

2. **File-based caching**: Before invoking FFmpeg, the script checks whether a sprite sheet for the current file already exists in mpv's cache directory. If it does, generation is skipped entirely and previews are available immediately.

3. **Cursor-to-timestamp mapping**: On seekbar hover, the script maps the cursor's X position to a video timestamp, computes the thumbnail index, and seeks into the BGRA binary at the correct byte offset to extract that frame.

4. **Direct overlay rendering**: The extracted raw BGRA slice is pushed directly to mpv's overlay API, no intermediate image format or additional decoding step required.

<br>

## 🛠️ TODO

- [x] Add Windows OS support
- [ ] Implement user configuration support
- [ ] Enable robust multi-resolution support
- [ ] Add customizable keybindings
- [ ] Improve preview accuracy
- [ ] Support low accuracy - high speed sprite generation mode
