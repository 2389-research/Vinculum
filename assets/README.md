# Vinculum logo assets

Palette: ink #18212B · parchment #F4F0E6 · cobalt #315C9B · rubric #B94A48
Wordmark typeface: STIX Two Text SemiBold.

## svg/
- vinculum-mark-{cobalt,ink,parchment}.svg — bare mark, transparent bg
- vinculum-appicon-square.svg — full-bleed square for Apple (Apple masks corners)
- vinculum-icon-linux.svg — rounded parchment tile, transparent corners

## apple/
AppIcon-{size}.png — drop into an .xcassets AppIcon set (1024 = App Store master).
Full-bleed squares; iOS/macOS apply the mask.

## linux/
hicolor/{N}x{N}/apps/vinculum.png — install to /usr/share/icons/hicolor/…
Plus use vinculum-icon-linux.svg at hicolor/scalable/apps/vinculum.svg.
