<h1 align="center">- mpv-config -</h1>
<h3 align="center"><samp>my personal mpv config files</samp></h3>

<img width="2560" height="1440" alt="showcase000" src="https://github.com/user-attachments/assets/b1738631-4b61-439b-a69a-801e6ff6615b" />

<img width="2560" height="1440" alt="showcase001" src="https://github.com/user-attachments/assets/2b2c54fd-6620-4fa5-a39b-e12aee4e9664" />

<img width="2560" height="1440" alt="showcase002" src="https://github.com/user-attachments/assets/0d9715e5-6b84-4dc5-9988-d1303182b35d" />

<img width="2560" height="1440" alt="showcase003" src="https://github.com/user-attachments/assets/0a410c37-5af1-43e4-987d-f7d4a0f70e99" />

<img width="2560" height="1440" alt="showcase004" src="https://github.com/user-attachments/assets/18cb0db5-6687-4f6f-90a0-a60ab03f8a5b" />


## Requirements

- mpv  
- ffmpeg  
- yt-dlp  

## Installation:
- **Windows:**
	- https://github.com/shinchiro/mpv-winbuild-cmake/releases  
	- https://github.com/zhongfly/mpv-winbuild/releases  
- **macOS:**
	- `brew install mpv`
- **Linux:**
	- Fedora
		- `sudo dnf install mpv`
	- Arch Linux / Manjaro
		- `sudo pacman -S mpv`
	- Ubuntu / Debian-based
		- `sudo apt update && sudo apt install mpv`

## Download Tips for Windows:
- 64 bit - mpv-x86_64-YYYYMMDD-git - for maximum compatibility
- 64 bit - mpv-x86_64-v3-YYYYMMDD-git - recommended for most modern systems (Intel Haswell 2013+, AMD Zen+)
- ARM64 - mpv-aarch64-YYYYMMDD-git - for Windows on ARM devices

## Setup

1. Extract mpv-x86_64-v3-YYYYMMDD-git.7z
2. Rename folder to `mpv`  
3. Move `mpv` to
    -   **Windows:**
		- **Option I:** 
			- `C:\Users\%Username%\AppData\Roaming\mpv`
		- **Option II:** 
			- Move `mpv` anywhere you like
4. Run `mpv-install.bat` or `register.bat` (for file associations)

- 	**Linux and macOS:** `~/.config/mpv`

## Folder Structure

    mpv/
    │   ffmpeg.exe
    │   mpv.exe
    │   updater.bat
    │   yt-dlp.exe
    │
    └── portable_config/
        │   input.conf
        │   mpv.conf
        │   watch_history.jsonl
        │   profiles.conf
        │
        ├── cache/
        │   ├── shaders_cache
        │   └── watch_later
        │
        ├── fonts/
        │   └── ryo-icons.ttf
        │
        ├── script-opts/
        │   ├── anilist_rpc.conf
        │   ├── media_rpc.conf
        │   ├── ryo-osc.conf
        │   ├── deband-cycle.conf
        │   ├── subtitle.conf
        │   ├── console.conf
        │   └── stats.conf
        │
        ├── scripts/
        │   ├── anilist_rpc.lua
        │   ├── media_rpc.lua
        │   ├── ryo-osc.lua
		│	├── lang-seek.lua
        │   ├── deband-cycle.lua
        │   ├── subtitle.lua
        │   ├── thumbfast.lua
        │   ├── evafast.lua
        │   ├── silentskip.lua
        │   └── webm.lua
        │
        └── shaders/
            └── .glsl files


## Scripts
- **[ryo-osc](https://github.com/Xightify/ryo-osc)** - My personal OSC fork based on **[hayase-osc](https://github.com/nekoxuee/hayase-osc)**.
- **deband-cycle, anilist_rpc, media_rpc, subtitle, lang-seek** are all made by me.
- **[evafast](https://github.com/po5/evafast)** - Fast-forwarding and seeking on a single key, with quality of life features like a slight slowdown when subtitles are shown.
- **[silentskip](https://github.com/nekoxuee/mpv-config/blob/main/scripts/silentskip.lua)** - Skip intros/endings manually, with silence-detection fallback.
- **[thumbfast](https://github.com/po5/thumbfast)** - High-performance on-the-fly thumbnailer script for mpv.
- **[webm](https://github.com/ekisu/mpv-webm)** - Quickly create video clips.

## Shaders
- **[AniSD ArtCNN](https://github.com/Sirosky/Upscale-Hub/releases/tag/AniSD-ArtCNN)**
- **[Ani4K v2 ArtCNN](https://github.com/Sirosky/Upscale-Hub/releases/tag/Ani4k-v2-ArtCNN)**
- **[ArtCNN](https://github.com/Artoriuz/ArtCNN)**
- **[CfL_Prediction](https://github.com/Artoriuz/glsl-chroma-from-luma-prediction)**
- **[Anime4k](https://github.com/bloc97/Anime4K)**

## Fonts
- Gandhi Sans  
- Century Gothic Bold
- Netflix Sans Bold
- Gabarito Regular
- JetBrainsMono Regular

## Tested Hardware

- Desktop: Ryzen 9 9950X3D, RTX 5080, 64 GB DDR5, Windows 11 Pro
- Laptop: Core i7-12700H, RTX 3070, 32 GB DDR5, Windows 11 Pro, Fedora

## Fix NVIDIA Overlay Issue

Alt + Z → Settings → Notifications → Disable "Open/close in-game overlay"

## References
- **[iamscum](https://iamscum.wordpress.com/guides/videoplayback-guide/mpv-conf/)**
- **[mpv manual](https://mpv.io/manual/stable/)**

## Other Configs
- https://github.com/nekoxuee/mpv-config
- https://github.com/Zabooby/mpv-config/
- https://github.com/tuilakhanh/mpv-config/
- https://github.com/itsmeipg/mpv-config/
- https://github.com/noelsimbolon/mpv-config/
- https://github.com/HongYue1/mpv-config
