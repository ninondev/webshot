# webshot

Turn a local HTML file into a PNG with the WebKit already on your Mac.

Unlike Quick Look, it runs the page's JavaScript before it takes the picture. `make test` renders a plain page, a dark-mode page and a page built by JavaScript, then checks the PNG size and sampled pixel colors; 13 checks pass on macOS 27 (Apple silicon), including the timeout and bad-input paths.

macOS 14 or later only. Output follows WebKit, so it can differ from Chrome. Fonts are the fonts installed on the Mac, plus fonts the page loads. No browser, Node, window, or screen capture is used.

## Build and use

Install Apple's Command Line Tools or Xcode with Swift 6 or later, then build:

```sh
nice -n 10 make
```

```sh
./build/webshot page.html out.png --width 1280 --scale 2 --theme light
```

The page is laid out at the CSS width and captured to its full height, up to `--max-height`. The output is one sRGB PNG. JavaScript runs on the page. Quick Look does not run page JavaScript; webshot needs no Chrome installation.

## Options

| Option | Meaning | Default |
| --- | --- | --- |
| `--width px` | Layout width in CSS pixels | `1280` |
| `--scale number` | Output pixels per CSS pixel | `2` |
| `--theme light\|dark` | Appearance, including `prefers-color-scheme` | `light` |
| `--wait ms` | Extra wait after fonts and images are ready | `0` |
| `--max-height px` | Maximum captured height in CSS pixels | `16000` |
| `--clip x,y,w,h` | Rectangle in CSS pixels, measured from the document's top left | Full page |
| `--js "expr"` | Evaluate an expression after waiting and print its result | None |
| `--timeout ms` | Deadline from renderer startup through PNG writing | `15000` |
| `--help` | Print usage | |

`--clip` must fit inside the layout width and captured height. Pixel dimensions are the CSS capture dimensions multiplied by scale, rounded to the nearest integer. Output is limited to 64 million pixels, 32768 pixels wide, and 65536 pixels high. Layout width is limited to 16384 CSS pixels, height to 65536, and scale to 16. Wait and timeout are limited to 3600000 ms.

`--js` runs in the page's JavaScript context. Promises are awaited. Strings print as plain text; other JSON-compatible values print as JSON. `undefined` prints as `undefined`. An exception or a result that cannot be serialized fails the job. DOM changes from the expression are included in the capture.

Status and errors go to stderr; stdout is reserved for `--js` results and help. Exit codes: `0` success, `1` load/render/write failure, `2` invalid arguments or unreadable input, `3` timeout. A printed JavaScript result does not guarantee that the later PNG write succeeded. Check the exit code.

## Limits

Local assets must be inside the HTML file's directory or its subdirectories. Linked network resources still depend on the page and its connection. There is no persistent browser profile.

Fonts and HTML images are awaited; lazy images are asked to load eagerly. A broken HTML image fails the job. Background images, video, WebGL, animations, and work started later by timers have no general readiness signal. Use `--wait` for delayed content. Capture uses WebKit's snapshot API, with no window attached to the view; support in a logged-out session or a restricted sandbox still needs testing.

The viewport grows to the measured document height before capture. Layouts based on viewport height, sticky elements, and fixed elements may change when it grows. This is a document render, not a screen screenshot.

## Test

```sh
nice -n 10 make test
```

The shell runner uses `sips` for dimensions and one-pixel crops. A small Swift ImageIO helper checks the cropped colors. It also tests clipping, height limits, fractional scale, argument errors, and timeout. Test images and logs are kept in a temporary directory printed by the runner. Set `WEBSHOT_TEST_TMP` to choose that directory's parent.

## License and contributions

GPL-3.0-only. See [LICENSE](LICENSE).

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and [CLA.md](CLA.md).

If this was useful to you, a star helps other people find it.
