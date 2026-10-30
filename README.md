<p align="center">
  <img src="docs/brand/logo.jpg" width="280" alt="popocu: a yellow character with a notch-shaped tuft, headphones and a play-button mouth">
</p>

<p align="center">
  <i>poni poni lucu</i> — a cute companion that lives in your MacBook's notch.<br>
  Time-synced lyrics for Spotify and Apple Music, with more to come.
</p>

<p align="center">
  <img src="Resources/screenshot.png" width="640" alt="popocu expanded view with Japanese lyrics, romanization and translation">
</p>

<p align="center">
  <img src="docs/brand/music.jpg" width="160" alt="Music">
  <img src="docs/brand/focus.jpg" width="160" alt="Focus">
  <img src="docs/brand/prayer.jpg" width="160" alt="Prayer">
  <img src="docs/brand/shelf.jpg" width="160" alt="Shelf">
</p>

---

## Features

**Music & lyrics**
- **Synced lyrics** under the notch, with a full lyrics view on hover, optional **karaoke** fill
- **Playback controls**: play/pause, skip, seek, volume, shuffle and repeat
- **Romanization** for Japanese, Korean, Chinese and other non-Latin lyrics
- **Translation** of lyrics into 8 languages, on-device (macOS 15+)
- **Lyrics picker**, copy a line or the whole song, or copy a lyric **card as an image**
- **Last.fm scrobbling** (bring your own free API key)

**Around the notch**
- **Pomodoro** with focus/break cycles, daily stats, water & stand-up reminders
- **Prayer times & adhan** (Indonesian Ministry of Religious Affairs method), automatic location
  or 23 cities, Ramadan mode with Imsak and an iftar countdown; silent while your mic is in use
- **File shelf**: drag files onto the notch, drag them out later, or AirDrop them
- **Camera mirror** and **clipboard history** (optional)
- **Charger, low battery and Bluetooth headphone** banners

**Stays out of the way**
- One thing at a time: a clear priority between music, focus and prayer
- Click-through lyrics that fade as your cursor approaches; each side of the notch slides away
  when you need the menu bar behind it
- Quiet during macOS Focus, respects Reduce Motion, hides from screen sharing (optional)
- A menu bar face that changes expression: peeking, looking up, focused, asleep
- English and Indonesian interface

## Requirements

- macOS 14 Sonoma or later (lyric translation requires macOS 15)
- A MacBook with a notch (other Macs show a compact pill at the top of the screen)
- Spotify desktop app and/or Apple Music

## Installation

### Download

Grab `popocu.zip` from the [latest release](https://github.com/rezaprahenda/popocu/releases/latest),
unzip it and move `popocu.app` to `/Applications`.

The app is not notarized, so macOS may say it "can't be opened" or "is damaged". Run this once:

```bash
xattr -dr com.apple.quarantine /Applications/popocu.app
```

### Build from source

Building requires the Xcode Command Line Tools.

```bash
xcode-select --install          # if not installed yet
git clone https://github.com/rezaprahenda/popocu.git
cd popocu
./build.sh install              # builds and copies the app to /Applications
```

On first launch, allow popocu to control Spotify or Music when prompted.
This permission is used only to read the current track and send playback commands.

## Usage

- Play a song. The notch shows the current lyric line.
- Hover over the notch for the full view and controls.
- Use the menu bar icon for settings.

## Privacy

popocu has no account, analytics or tracking. It sends the track title, artist,
album and duration to [LRCLIB](https://lrclib.net) to fetch lyrics, and to the iTunes
Search API to fetch artwork when needed. Romanization, translation and prayer times run
on-device; with automatic location, the city name is looked up through Apple's maps service.
Last.fm only receives what you play if you connect it. Clipboard history stays in memory and
skips items marked as passwords. The camera mirror only runs while its page is open.

## Acknowledgements

Lyrics are provided by [LRCLIB](https://lrclib.net), a free and open lyrics database.

## License

Released under the [MIT License](LICENSE).

popocu is an independent project and is not affiliated with Spotify or Apple.
Spotify and Apple Music are trademarks of their respective owners.
