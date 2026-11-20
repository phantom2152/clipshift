# ClipShift

ClipShift is a native macOS app for converting local media files and downloading videos or playlists from links.

## Features

- Convert media by dropping files or folders into the app
- Download from URLs and playlists
- Convert downloaded media automatically
- Export to MP4, H.265, MOV, MKV, WebM, GIF, MP3, M4A, WAV, or remux to MKV
- Choose quality presets and configure format-specific settings
- Track conversion and download progress

## Requirements

- macOS 14 or later
- Swift 6.4 or later
- [ffmpeg](https://ffmpeg.org/)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) for URL and playlist downloads

Install the external tools with Homebrew:

```bash
brew install ffmpeg yt-dlp
```

ClipShift checks the common Apple Silicon and Intel Homebrew paths. You can also select custom executable paths under **Settings > Tools**.

## Running

From the project directory:

```bash
swift run
```

## Settings

Open **ClipShift > Settings** to configure:

- Conversion formats, quality, and encoder options
- Download location, filenames, playlists, and audio-only downloads
- ffmpeg and yt-dlp paths
- Notifications, sounds, sleep prevention, and window behavior
