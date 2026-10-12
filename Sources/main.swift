// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Ninon
import AppKit
import WebKit
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("webshot: \(message)\n".utf8))
    exit(code)
}

let usage = """
Usage: webshot page.html out.png [options]
  --width px        CSS layout width (default: 1280)
  --scale number    Output pixels per CSS pixel (default: 2)
  --theme light|dark (default: light)
  --wait ms         Extra wait after fonts and images (default: 0)
  --max-height px   Crop full-page height in CSS pixels (default: 16000)
  --clip x,y,w,h    Capture a rectangle in CSS pixels, from top left
  --js expr         Evaluate after waiting; print string or JSON to stdout
  --timeout ms      Whole-job deadline (default: 15000)
  --help            Show help
Output: one sRGB PNG; status on stderr. Exit: 0 success, 1 render/write
failure, 2 invalid input, 3 timeout. macOS 14 or later.
"""

struct InputError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

struct Options {
    let page: URL
    let output: URL
    var width = 1280.0
    var scale = 2.0
    var theme = "light"
    var wait = 0.0
    var maxHeight = 16000.0
    var clip: CGRect?
    var expression: String?
    var timeout = 15000.0

    static func parse(_ args: [String]) throws -> Options {
        guard args.count >= 2 else { throw InputError(usage) }
        var options = Options(page: URL(fileURLWithPath: args[0]).standardizedFileURL,
                              output: URL(fileURLWithPath: args[1]).standardizedFileURL)
        func number(_ value: String, _ name: String, positive: Bool = true) throws -> Double {
            guard let parsed = Double(value), parsed.isFinite,
                  positive ? parsed > 0 : parsed >= 0 else {
                throw InputError("\(name) requires a finite \(positive ? "positive" : "non-negative") number")
            }
            return parsed
        }
        var index = 2
        while index < args.count {
            let name = args[index]
            guard ["--width", "--scale", "--theme", "--wait", "--max-height", "--timeout", "--js", "--clip"].contains(name) else {
                throw InputError("unknown option \(name); use --help")
            }
            guard index + 1 < args.count else { throw InputError("missing value for \(name)") }
            let value = args[index + 1]
            switch name {
            case "--width": options.width = try number(value, name)
            case "--scale": options.scale = try number(value, name)
            case "--theme":
                guard ["light", "dark"].contains(value) else { throw InputError("--theme must be light or dark") }
                options.theme = value
            case "--wait": options.wait = try number(value, name, positive: false)
            case "--max-height": options.maxHeight = try number(value, name)
            case "--timeout": options.timeout = try number(value, name)
            case "--js": options.expression = value
            case "--clip":
                let parts = value.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 4 else { throw InputError("--clip requires x,y,w,h") }
                options.clip = try CGRect(x: number(parts[0], name, positive: false),
                                          y: number(parts[1], name, positive: false),
                                          width: number(parts[2], name), height: number(parts[3], name))
            default: throw InputError("unknown option \(name); use --help")
            }
            index += 2
        }
        guard options.width <= 16384, options.maxHeight <= 65536, options.scale <= 16,
              options.timeout <= 3600000, options.wait <= 3600000 else {
            throw InputError("limits: width 16384, height 65536, scale 16, wait/timeout 3600000 ms")
        }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: options.page.path, isDirectory: &directory),
              !directory.boolValue, FileManager.default.isReadableFile(atPath: options.page.path) else {
            throw InputError("cannot read HTML file: \(options.page.path)")
        }
        guard options.page.resolvingSymlinksInPath() != options.output.resolvingSymlinksInPath() else {
            throw InputError("input and output must be different files")
        }
        return options
    }
}

@MainActor
final class Renderer: NSObject, WKNavigationDelegate {
    let options: Options
    let web: WKWebView
    private var loaded = false
    private let deadline: DispatchSourceTimer
    private var capture = CGRect.zero

    init(_ options: Options, deadline: DispatchSourceTimer) {
        self.options = options
        self.deadline = deadline
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.suppressesIncrementalRendering = true
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: options.width, height: 1),
                        configuration: configuration)
        super.init()
        web.navigationDelegate = self
        web.appearance = NSAppearance(named: options.theme == "dark" ? .darkAqua : .aqua)
    }

    func start() {
        web.loadFileURL(options.page, allowingReadAccessTo: options.page.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("load failed for \(options.page.path): \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("load failed for \(options.page.path): \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("WebKit content process terminated while rendering \(options.page.path)")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
        } else if navigationAction.targetFrame?.isMainFrame == true,
                  navigationAction.request.url?.isFileURL != true {
            decisionHandler(.cancel)
            fail("page tried to navigate away from the local HTML file")
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !loaded else { fail("page navigated during rendering") }
        loaded = true
        web.callAsyncJavaScript(Self.readyScript + "return true;", arguments: ["wait": options.wait], in: nil, in: .page) { [self] result in
            switch result {
            case .failure(let error): fail("page readiness failed: \(error.localizedDescription)")
            case .success: evaluateExpression()
            }
        }
    }

    private static let readyScript = """
    async function ready() {
      for (const image of document.images) image.loading = 'eager';
      await document.fonts.ready;
      await Promise.all(Array.from(document.images, async image => {
        if (!image.complete) await new Promise(resolve => {
          image.addEventListener('load', resolve, {once: true});
          image.addEventListener('error', resolve, {once: true});
        });
        if (image.naturalWidth === 0) throw new Error('image failed to load: ' + image.src);
        await image.decode();
      }));
    }
    await ready();
    await new Promise(resolve => setTimeout(resolve, wait + 50));
    await ready();
    """

    private func evaluateExpression() {
        guard let expression = options.expression else { measure(); return }
        web.callAsyncJavaScript("""
        const value = await (0, eval)(expression);
        if (typeof value === 'string') return value;
        if (value === undefined) return 'undefined';
        const json = JSON.stringify(value);
        if (json === undefined) throw new Error('expression result cannot be printed as JSON');
        return json;
        """, arguments: ["expression": expression], in: nil, in: .page) { [self] result in
            switch result {
            case .failure(let error): fail("--js failed: \(error.localizedDescription)")
            case .success(let value):
                guard let text = value as? String else { fail("--js returned an unsupported result") }
                print(text)
                measure()
            }
        }
    }

    private func measure() {
        web.callAsyncJavaScript(Self.readyScript + """
        const root = document.documentElement, body = document.body;
        return Math.ceil(Math.max(1, root.scrollHeight, root.offsetHeight,
          body ? body.scrollHeight : 0, body ? body.offsetHeight : 0));
        """, arguments: ["wait": 0], in: nil, in: .page) { [self] result in
            switch result {
            case .failure(let error): fail("page measurement failed: \(error.localizedDescription)")
            case .success(let value):
                guard let height = (value as? NSNumber)?.doubleValue, height.isFinite, height > 0 else {
                    fail("WebKit returned an invalid document height")
                }
                let boundedHeight = min(height, options.maxHeight)
                capture = options.clip ?? CGRect(x: 0, y: 0, width: options.width, height: boundedHeight)
                guard capture.maxX <= options.width, capture.maxY <= boundedHeight else {
                    fail("--clip must fit within width \(options.width) and captured height \(boundedHeight)", code: 2)
                }
                let width = (capture.width * options.scale).rounded()
                let pixelsHigh = (capture.height * options.scale).rounded()
                guard width >= 1, pixelsHigh >= 1, width <= 32768, pixelsHigh <= 65536,
                      width * pixelsHigh <= 64_000_000 else {
                    fail("output exceeds limits: 32768 pixels wide, 65536 high, or 64000000 pixels")
                }
                web.setFrameSize(NSSize(width: options.width, height: boundedHeight))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.snapshot() }
            }
        }
    }

    private func snapshot() {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = capture
        configuration.snapshotWidth = NSNumber(value: capture.width * options.scale)
        // An unattached view has no screen updates to wait for.
        configuration.afterScreenUpdates = false
        web.takeSnapshot(with: configuration) { [self] image, error in
            if let error { fail("WebKit snapshot failed: \(error.localizedDescription)") }
            guard let image else { fail("WebKit returned no snapshot") }
            do { try write(image) }
            catch { fail("cannot write PNG to \(options.output.path): \(error.localizedDescription)") }
            deadline.cancel()
            exit(0)
        }
    }

    private func write(_ image: NSImage) throws {
        let width = Int((capture.width * options.scale).rounded())
        let height = Int((capture.height * options.scale).rounded())
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let source = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw InputError("cannot allocate sRGB image")
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        guard let pixels = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw InputError("cannot create PNG encoder")
        }
        CGImageDestinationAddImage(destination, pixels, nil)
        guard CGImageDestinationFinalize(destination) else { throw InputError("PNG encoding failed") }
        try (data as Data).write(to: options.output, options: .atomic)
        FileHandle.standardError.write(Data("webshot: wrote \(options.output.path) (\(width)x\(height))\n".utf8))
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] { print(usage); exit(0) }
let options: Options
do { options = try Options.parse(arguments) }
catch { fail(String(describing: error), code: 2) }
// The handler is main-actor isolated (top-level code), so it must fire on the main queue;
// NSApplication.run services the main queue, and loading never blocks it.
let deadline = DispatchSource.makeTimerSource(queue: .main)
let milliseconds = options.timeout
deadline.schedule(deadline: .now() + milliseconds / 1000)
deadline.setEventHandler { fail("timed out after \(milliseconds) ms", code: 3) }
deadline.resume()
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer(options, deadline: deadline)
renderer.start()
app.run()
