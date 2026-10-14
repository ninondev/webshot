# webshot

Render a local HTML file to a PNG using the WebKit framework built into macOS.

Quick Look skips page JavaScript, whereas `webshot` executes scripts before capturing. `make test` renders a plain page, a dark-mode page, and a JavaScript-generated page, verifying PNG dimensions and sampled pixel colors; all 13 checks pass on macOS 27 (Apple silicon), covering timeout and invalid-input paths.

Requires macOS 14 or later. Rendering uses WebKit, so output may differ from Chrome. Text renders using system fonts installed on the Mac alongside any fonts loaded by the page. Everything runs without a browser, Node, windows, or screen capture.

## Build and use

Install Apple's Command Line Tools or Xcode with Swift 6 or later, then build:

```sh
nice -n 10 make
```

```sh
./build/webshot page.html out.png --width 1280 --scale 2 --theme light
```

`webshot` lays out the page at the given CSS width, runs its JavaScript, and captures the full height up to `--max-height` as a single sRGB PNG. Quick Look does not execute page JavaScript, and `webshot` requires no Chrome installation.

## Options

| Option | Meaning | Default |
| --- | --- | --- |
| `--width px` | Layout width in CSS pixels | `1280` |
| `--scale number` | Output pixels per CSS pixel | `2` |
| `--theme light\|dark` | Appearance, including `prefers-color-scheme` | `light` |
| `--wait ms` | Additional wait after fonts and images finish loading | `0` |
| `--max-height px` | Maximum captured height in CSS pixels | `16000` |
| `--clip x,y,w,h` | Capture rectangle in CSS pixels from the document's top-left corner | Full page |
| `--js "expr"` | Evaluate an expression after the wait period and print its result | None |
| `--timeout ms` | Total time limit from renderer startup to PNG write completion | `15000` |
| `--help` | Print usage |  |

The `--clip` region must fit within the layout width and captured height. Output pixel dimensions equal the CSS capture dimensions multiplied by `--scale`, rounded to the nearest integer. Output cannot exceed 64 million total pixels, 32768 pixels in width, or 65536 pixels in height. Layout width is capped at 16384 CSS pixels, height at 65536, and scale at 16. Both `--wait` and `--timeout` have a maximum of 3600000 ms.

`--js` evaluates inside the page's JavaScript context and awaits Promises. Strings print as plain text, `undefined` prints as `undefined`, and other JSON-compatible values print as JSON. Uncaught exceptions or unserializable return values fail the run. Any DOM mutations made by the expression appear in the final PNG.

Status messages and errors go to `stderr`, leaving `stdout` strictly for `--js` output and `--help`. Exit codes: `0` for success, `1` for load, render, or write failure, `2` for invalid arguments or unreadable input, and `3` for timeout. Because a printed JavaScript result does not mean the subsequent PNG write succeeded, always check the exit code.

## Limits

Local assets must reside inside the HTML file's directory or its subdirectories. External network resources depend on the page and active network availability. Runs use no persistent browser profile.

`webshot` waits for fonts and HTML images to load, and asks lazy images to load eagerly. Any broken HTML image fails the run. Background images, video, WebGL, animations, and timer-driven tasks provide no standard readiness signal; use `--wait` when capturing delayed content. Captures rely on WebKit's snapshot API with an unattached view, and behavior inside logged-out sessions or restricted sandboxes remains untested.

Before capture, the viewport expands to match the measured document height. Viewport-relative units, sticky elements, and fixed elements may shift when the viewport grows. The output represents a full document render rather than a screen screenshot.

## Test

```sh
nice -n 10 make test
```

The test script uses `sips` to verify image dimensions and crop single pixels, passing them to a small Swift ImageIO helper to check pixel colors. It also covers clipping, height limits, fractional scaling, invalid arguments, and timeouts. Test images and logs stay in a temporary directory printed by the runner; set `WEBSHOT_TEST_TMP` to change its parent directory.

## License and contributions

MIT. See [LICENSE](LICENSE).

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).
