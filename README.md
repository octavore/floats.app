# floats

<p align="center">
  <img src="docs/images/macos-floats-icon.png" width="96" height="96" alt="floats app icon" />
</p>

A single floating macOS sticky note, with markdown formatting and auto-saved text.

## Requirements

- macOS 14+
- [strudel](https://github.com/octavore/strudel) for development

## Development

```sh
strudel run               # builds and runs the app
strudel build --install   # builds and installs to /Applications
strudel clean
```

### Testing

```sh
swift test --skip PerformanceTests  # fast tests only
swift test                          # all tests, slower
```

## Releasing

This repo uses [strudel-release-action](https://github.com/octavore/strudel-release-action) for releasing with github actions.

## Credits

<a href="https://www.flaticon.com/free-icons/birthday" title="birthday icons">Balloon icon created by Pixel perfect - Flaticon</a>

## License

MIT
