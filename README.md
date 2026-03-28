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
| Windows | `C:/Users/username/AppData/Roaming/mpv/scripts/` |

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

## 🎛️ Configuration

Create a config file at `<OS-SPECIFIC-DIR>/mpv/script-opts/mpv_seekpeek.conf` to customize the script's behavior.
(Sample config file: [mpv_seekpeek.conf](mpv_seekpeek.conf))

You can also pass options via the command line: `mpv --script-opts=mpv_seekpeek-auto_start=no video.mp4`

### Options

| Option | Default | Description |
| --- | --- | --- |
| `auto_start` | `yes` | Auto-start sprite generation on playback. Set to `no` to trigger manually with a keybind. |
| `delete_sprite_on_exit` | `no` | Delete the sprite file when player quits. |
| `auto_fullscreen` | `yes` | Automatically enter fullscreen on playback start. |
| `preview_enabled` | `yes` | Enable or disable preview overlay. |
| `message_duration` | `3` | Duration for OSD messages in seconds. |
| `thumbnail_interval` | `5` | Seconds between thumbnail samples. (Higher value makes sprite size lower) |
| `preview_width` | `240` | Preview thumbnail width in pixels. |
| `preview_height` | `100` | Preview thumbnail height in pixels. |
| `sprite_grid_rows` | `30` | Sprite sheet grid rows. |
| `sprite_grid_cols` | `30` | Sprite sheet grid columns. |
| `key_generate` | `T` | Key to manually trigger sprite generation. |
| `key_regenerate` | `Ctrl+T` | Key to force regenerate sprite (delete existing and rebuild). |
| `key_toggle_preview` | `Ctrl+S` | Key to toggle preview overlay on/off. |
| `key_delete_sprite` | `Alt+T` | Key to delete the cached sprite for the current file. |

### Example config

```ini
# Disable automatic sprite generation, generate on key press instead
auto_start=no

# Clean up sprite files when done
delete_sprite_on_exit=yes

# Don't force fullscreen
auto_fullscreen=no

# Use a larger preview
preview_width=320
preview_height=180
```

<br>

## ⌨️ Keybindings

| Key | Action |
| --- | --- |
| `T` | Manually trigger sprite sheet generation (useful when `auto_start=no`, or to regenerate) |
| `Ctrl+T` | Force regenerate sprite sheet (deletes existing cache and rebuilds) |
| `Ctrl+S` | Toggle preview overlay on/off |
| `Alt+T` | Delete the cached sprite file for the current video |

All keybindings are configurable via the config file above, or via mpv's `input.conf`:

```
# input.conf example:

Ctrl+t script-binding seekpeek-generate
Ctrl+Shift+t script-binding seekpeek-regenerate
p script-binding seekpeek-toggle-preview
Ctrl+Shift+d script-binding seekpeek-delete-sprite
```

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
- [x] Implement user configuration support
- [x] Add customizable keybindings
- [ ] Enable robust multi-resolution support
- [ ] Improve preview accuracy
- [ ] Support low accuracy - high speed sprite generation mode
- [ ] Support for 3rd-party OSC's like ModernZ and UOSC
- [ ] Support custom mpv-seekpeek sprites directory
