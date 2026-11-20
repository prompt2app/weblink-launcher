// 网页快开管理 —— 管理“名称 → 网址”，为每一项在 ~/Applications/网页快开/ 生成一个可被 Spotlight 搜到的启动入口
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 数据与路径

struct WebLink: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var url: String
    var appName: String?
}

enum Paths {
    static let fm = FileManager.default
    static let home = fm.homeDirectoryForCurrentUser
    static let appsDir = home.appendingPathComponent("Applications/网页快开", isDirectory: true)
    static let supportDir = home.appendingPathComponent("Library/Application Support/网页快开", isDirectory: true)
    static let iconsDir = supportDir.appendingPathComponent("icons", isDirectory: true)
    static let dataFile = supportDir.appendingPathComponent("links.json")
    static func iconPNG(_ id: String) -> URL { iconsDir.appendingPathComponent("\(id).png") }
    static func ensure() {
        try? fm.createDirectory(at: appsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)
    }
}

func loadLinks() -> [WebLink] {
    guard let d = try? Data(contentsOf: Paths.dataFile) else { return [] }
    return (try? JSONDecoder().decode([WebLink].self, from: d)) ?? []
}

func saveLinks(_ links: [WebLink]) {
    Paths.ensure()
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    if let d = try? enc.encode(links) { try? d.write(to: Paths.dataFile, options: .atomic) }
}

// MARK: - 外部命令

let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

@discardableResult
func run(_ path: String, _ args: [String]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, "\(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

struct BuildError: LocalizedError {
    let msg: String
    var errorDescription: String? { msg }
}

// MARK: - 图标绘制

func pixelSize(_ img: NSImage) -> Int {
    let px = img.representations.map { $0.pixelsWide }.max() ?? 0
    return px <= 0 ? 1024 : px   // 0 表示矢量图（SVG/PDF）
}

func makeRep(_ n: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: n, height: n)
    return rep
}

func drawInto(_ rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)
    ctx?.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    body()
    ctx?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

let palette: [NSColor] = [
    NSColor(srgbRed: 0.23, green: 0.36, blue: 0.86, alpha: 1),
    NSColor(srgbRed: 0.13, green: 0.59, blue: 0.95, alpha: 1),
    NSColor(srgbRed: 0.10, green: 0.65, blue: 0.55, alpha: 1),
    NSColor(srgbRed: 0.93, green: 0.42, blue: 0.13, alpha: 1),
    NSColor(srgbRed: 0.85, green: 0.22, blue: 0.30, alpha: 1),
    NSColor(srgbRed: 0.55, green: 0.33, blue: 0.85, alpha: 1),
    NSColor(srgbRed: 0.20, green: 0.25, blue: 0.35, alpha: 1),
    NSColor(srgbRed: 0.78, green: 0.55, blue: 0.10, alpha: 1),
]

func paletteColor(_ name: String) -> NSColor {
    let h = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
    return palette[h % palette.count]
}

/// 从小图标里取主色，用作文字图标的底色
func dominantColor(_ img: NSImage) -> NSColor? {
    let n = 24
    let rep = makeRep(n)
    drawInto(rep) { img.draw(in: NSRect(x: 0, y: 0, width: n, height: n)) }
    var buckets: [Int: (w: Double, r: Double, g: Double, b: Double)] = [:]
    for x in 0..<n {
        for y in 0..<n {
            guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5 else { continue }
            let r = Double(c.redComponent), g = Double(c.greenComponent), b = Double(c.blueComponent)
            let mx = max(r, g, b), mn = min(r, g, b)
            if mn > 0.9 { continue }                 // 白色背景
            let sat = mx - mn
            if sat < 0.12 { continue }               // 灰色、黑色文字
            let key = Int(r * 4) * 25 + Int(g * 4) * 5 + Int(b * 4)
            let w = 1 + sat * 3
            let o = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (o.w + w, o.r + r * w, o.g + g * w, o.b + b * w)
        }
    }
    guard let best = buckets.values.max(by: { $0.w < $1.w }) else { return nil }
    var r = best.r / best.w, g = best.g / best.w, b = best.b / best.w
    let lum = 0.299 * r + 0.587 * g + 0.114 * b
    if lum > 0.68 { let k = 0.68 / lum; r *= k; g *= k; b *= k }   // 太亮时压暗，保证白字看得清
    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

func iconLetters(_ name: String) -> String {
    let t = name.trimmingCharacters(in: .whitespaces)
    guard let first = t.first else { return "?" }
    if first.isASCII {
        let upperRun = t.prefix(while: { $0.isASCII && ($0.isUppercase || $0.isNumber) })
        if upperRun.count >= 2 { return String(upperRun.prefix(2)) }
        return String(first).uppercased()
    }
    return String(first)
}

/// 生成 1024px 的 macOS 风格图标：清晰的大图放白底圆角方块里；没有图或图太小则画文字图标
func renderIcon(source: NSImage?, name: String) -> NSImage {
    let N: CGFloat = 1024, m: CGFloat = 100, side: CGFloat = 824
    let useImage = source.map { pixelSize($0) >= 64 && $0.size.width > 0 } ?? false
    let bg: NSColor = useImage ? .white : (source.flatMap(dominantColor) ?? paletteColor(name))
    let rep = makeRep(Int(N))
    drawInto(rep) {
        let path = NSBezierPath(roundedRect: NSRect(x: m, y: m, width: side, height: side), xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let sh = NSShadow()
        sh.shadowColor = NSColor.black.withAlphaComponent(0.28)
        sh.shadowBlurRadius = 28
        sh.shadowOffset = NSSize(width: 0, height: -12)
        sh.set()
        bg.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        if useImage, let src = source {
            let box = side * 0.66
            let sz = src.size
            let scale = min(box / sz.width, box / sz.height)
            let w = sz.width * scale, h = sz.height * scale
            src.draw(in: NSRect(x: (N - w) / 2, y: (N - h) / 2, width: w, height: h),
                     from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            let text = iconLetters(name)
            let fontSize: CGFloat = text.count >= 2 ? 360 : 460
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let s = NSAttributedString(string: text, attributes: attrs)
            let b = s.size()
            s.draw(at: NSPoint(x: (N - b.width) / 2, y: (N - b.height) / 2 + 8))
        }
    }
    let img = NSImage(size: NSSize(width: N, height: N))
    img.addRepresentation(rep)
    return img
}

func pngData(_ img: NSImage, size: Int) -> Data? {
    let rep = makeRep(size)
    drawInto(rep) { img.draw(in: NSRect(x: 0, y: 0, width: size, height: size)) }
    return rep.representation(using: .png, properties: [:])
}

// MARK: - 抓取网站图标

final class TrustAll: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let t = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: t))   // 只用于下载图标，内网自签证书也放行
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

let session: URLSession = {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = 8
    cfg.timeoutIntervalForResource = 15
    return URLSession(configuration: cfg, delegate: TrustAll(), delegateQueue: nil)
}()

func fetch(_ url: URL) async -> (Data, URL)? {
    var req = URLRequest(url: url)
    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36",
                 forHTTPHeaderField: "User-Agent")
    guard let (d, r) = try? await session.data(for: req),
          let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode) else { return nil }
    return (d, h.url ?? url)
}

func origin(_ u: URL) -> URL? {
    var c = URLComponents()
    c.scheme = u.scheme
    c.host = u.host
    c.port = u.port
    c.path = "/"
    return c.url
}

func htmlAttr(_ tag: String, _ name: String) -> String? {
    let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
    guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
    for i in 1...3 {
        if let r = Range(m.range(at: i), in: tag) { return String(tag[r]) }
    }
    return nil
}

func fetchFavicon(page: String) async -> NSImage? {
    guard let pu = URL(string: page) else { return nil }
    var cands: [URL] = []
    if let (d, final) = await fetch(pu) {
        let html = String(decoding: d.prefix(400_000), as: UTF8.self)
        let re = try! NSRegularExpression(pattern: "<link\\b[^>]*>", options: .caseInsensitive)
        var touch: [URL] = [], icons: [URL] = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            guard let r = Range(m.range, in: html) else { continue }
            let tag = String(html[r])
            guard let rel = htmlAttr(tag, "rel")?.lowercased(), rel.contains("icon"),
                  let href = htmlAttr(tag, "href"),
                  let u = URL(string: href.trimmingCharacters(in: .whitespaces), relativeTo: final)?.absoluteURL
            else { continue }
            if rel.contains("apple-touch") { touch.append(u) } else { icons.append(u) }
        }
        cands += touch + icons
        if let o = origin(final) { cands.append(o.appendingPathComponent("favicon.ico")) }
    }
    if let o = origin(pu) { cands.append(o.appendingPathComponent("favicon.ico")) }

    var best: NSImage?
    var bestPx = 0
    var seen = Set<String>()
    for c in cands where seen.insert(c.absoluteString).inserted {
        guard let (d, _) = await fetch(c), let img = NSImage(data: d), img.isValid, img.size.width > 0 else { continue }
        let px = pixelSize(img)
        if px > bestPx { best = img; bestPx = px }
        if bestPx >= 180 { break }
    }
    return best
}

// MARK: - 生成 / 删除启动入口

func safeAppName(_ name: String) -> String {
    let n = name.trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
    return (n.isEmpty ? "未命名" : n) + ".app"
}

func removeLauncher(_ appName: String?) {
    guard let appName else { return }
    let p = Paths.appsDir.appendingPathComponent(appName)
    guard Paths.fm.fileExists(atPath: p.path) else { return }
    run(lsregister, ["-u", p.path])
    if (try? Paths.fm.trashItem(at: p, resultingItemURL: nil)) == nil {
        try? Paths.fm.removeItem(at: p)
    }
}

/// 写图标、生成 .app，返回带新 appName 的记录
func installLink(_ link: WebLink, icon: NSImage) throws -> WebLink {
    Paths.ensure()
    guard let png = pngData(icon, size: 1024) else { throw BuildError(msg: "图标生成失败") }
    try png.write(to: Paths.iconPNG(link.id), options: .atomic)

    let appName = safeAppName(link.name)
    let work = Paths.fm.temporaryDirectory.appendingPathComponent("weblink-" + UUID().uuidString, isDirectory: true)
    try Paths.fm.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? Paths.fm.removeItem(at: work) }
    let app = work.appendingPathComponent(appName)

    let escaped = link.url.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let (code, out) = run("/usr/bin/osacompile", ["-o", app.path, "-e", "open location \"\(escaped)\""])
    guard code == 0 else { throw BuildError(msg: "osacompile 失败：\(out)") }

    // Info.plist：后台运行、去掉指向 Assets.car 的图标名（否则不显示自定义图标）、唯一 bundle id
    let plistURL = app.appendingPathComponent("Contents/Info.plist")
    let pd = try Data(contentsOf: plistURL)
    guard var plist = try PropertyListSerialization.propertyList(from: pd, format: nil) as? [String: Any] else {
        throw BuildError(msg: "读取 Info.plist 失败")
    }
    plist["LSUIElement"] = true
    plist.removeValue(forKey: "CFBundleIconName")
    plist["CFBundleIconFile"] = "applet"
    plist["CFBundleIdentifier"] = "local.weblink." + link.id
    plist["CFBundleName"] = link.name
    plist["CFBundleDisplayName"] = link.name
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
    try? Paths.fm.removeItem(at: app.appendingPathComponent("Contents/Resources/Assets.car"))

    // 图标 icns
    let iconset = work.appendingPathComponent("icon.iconset", isDirectory: true)
    try Paths.fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    for s in [16, 32, 128, 256, 512] {
        try pngData(icon, size: s)?.write(to: iconset.appendingPathComponent("icon_\(s)x\(s).png"))
        try pngData(icon, size: s * 2)?.write(to: iconset.appendingPathComponent("icon_\(s)x\(s)@2x.png"))
    }
    let icns = app.appendingPathComponent("Contents/Resources/applet.icns")
    try? Paths.fm.removeItem(at: icns)
    let (ic, iout) = run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", icns.path])
    guard ic == 0 else { throw BuildError(msg: "iconutil 失败：\(iout)") }

    run("/usr/bin/codesign", ["--force", "--deep", "-s", "-", app.path])

    // 替换旧入口（包括改名前的）
    removeLauncher(link.appName)
    removeLauncher(appName)
    let dest = Paths.appsDir.appendingPathComponent(appName)
    try Paths.fm.moveItem(at: app, to: dest)
    run("/usr/bin/touch", [dest.path])
    run(lsregister, ["-f", dest.path])
    run("/usr/bin/mdimport", [dest.path])

    var updated = link
    updated.appName = appName
    return updated
}

// MARK: - 状态

@MainActor
final class Store: ObservableObject {
    @Published var links: [WebLink] = []
    @Published var busy: String?
    @Published var errorText: String?
    @Published var iconVersion = 0
    @Published var editing: EditTarget?
    @Published var toDelete: WebLink?
    private var iconCache: [String: NSImage] = [:]

    init() {
        Paths.ensure()
        links = loadLinks()
    }

    func icon(for l: WebLink) -> NSImage {
        if let i = iconCache[l.id] { return i }
        let i = NSImage(contentsOf: Paths.iconPNG(l.id)) ?? renderIcon(source: nil, name: l.name)
        iconCache[l.id] = i
        return i
    }

    func nameTaken(_ name: String, except id: String?) -> Bool {
        links.contains { $0.id != id && safeAppName($0.name) == safeAppName(name) }
    }

    func save(original: WebLink?, name: String, url: String, icon: NSImage) {
        var link = original ?? WebLink(id: UUID().uuidString.lowercased(), name: name, url: url, appName: nil)
        link.name = name
        link.url = url
        busy = "正在生成「\(name)」…"
        Task.detached {
            do {
                let updated = try installLink(link, icon: icon)
                await MainActor.run {
                    if let i = self.links.firstIndex(where: { $0.id == updated.id }) {
                        self.links[i] = updated
                    } else {
                        self.links.append(updated)
                    }
                    saveLinks(self.links)
                    self.iconCache[updated.id] = nil
                    self.iconVersion += 1
                    self.busy = nil
                }
            } catch {
                await MainActor.run {
                    self.busy = nil
                    self.errorText = error.localizedDescription
                }
            }
        }
    }

    func delete(_ l: WebLink) {
        removeLauncher(l.appName)
        try? Paths.fm.removeItem(at: Paths.iconPNG(l.id))
        links.removeAll { $0.id == l.id }
        saveLinks(links)
    }

    func move(from: IndexSet, to: Int) {
        links.move(fromOffsets: from, toOffset: to)
        saveLinks(links)
    }
}

// MARK: - 界面

enum EditTarget: Identifiable {
    case new
    case edit(WebLink)
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let l): return l.id
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("网页快开").font(.title2.bold())
                    Text("按 ⌘空格，输入名称（或开头几个字母）回车即可打开")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("打开目录") { NSWorkspace.shared.open(Paths.appsDir) }
                Button { store.editing = .new } label: { Label("添加", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("n")
            }
            .padding(16)
            Divider()

            if store.links.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "link").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("还没有网址，点右上角「添加」").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.links) { l in
                        row(l)
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
                .listStyle(.inset)
                .id(store.iconVersion)
            }

            if let b = store.busy {
                Divider()
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(b).font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .sheet(item: $store.editing) { t in
            switch t {
            case .new: EditView(original: nil) { store.editing = nil }.environmentObject(store)
            case .edit(let l): EditView(original: l) { store.editing = nil }.environmentObject(store)
            }
        }
        .confirmationDialog("删除「\(store.toDelete?.name ?? "")」？", isPresented: Binding(
            get: { store.toDelete != nil }, set: { if !$0 { store.toDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let l = store.toDelete { store.delete(l) }
                store.toDelete = nil
            }
        } message: {
            Text("启动入口会移到废纸篓。")
        }
        .alert("出错了", isPresented: Binding(
            get: { store.errorText != nil }, set: { if !$0 { store.errorText = nil } }
        )) {
            Button("好") { store.errorText = nil }
        } message: {
            Text(store.errorText ?? "")
        }
    }

    func row(_ l: WebLink) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: store.icon(for: l))
                .resizable().interpolation(.high)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(l.name).font(.body.weight(.medium))
                Text(l.url).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { if let u = URL(string: l.url) { NSWorkspace.shared.open(u) } } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.borderless).help("打开")
            Button { store.editing = .edit(l) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).help("编辑")
            Button { store.toDelete = l } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("删除")
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.editing = .edit(l) }
    }
}

enum IconMode { case existing, image, letter, unset }

@MainActor
final class EditModel: ObservableObject {
    @Published var name: String
    @Published var url: String
    @Published var mode: IconMode
    @Published var source: NSImage?
    @Published var fetching = false
    @Published var note: String?
    init(_ original: WebLink?) {
        name = original?.name ?? ""
        url = original?.url ?? ""
        mode = original == nil ? .unset : .existing
    }
}

struct EditView: View {
    @EnvironmentObject var store: Store
    let original: WebLink?
    let close: () -> Void
    @StateObject private var m: EditModel

    init(original: WebLink?, close: @escaping () -> Void) {
        self.original = original
        self.close = close
        _m = StateObject(wrappedValue: EditModel(original))
    }

    var normalizedURL: String {
        let u = m.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty || u.contains("://") { return u }
        return "https://" + u
    }

    var trimmedName: String { m.name.trimmingCharacters(in: .whitespaces) }

    var preview: NSImage {
        switch m.mode {
        case .existing: return original.map { store.icon(for: $0) } ?? renderIcon(source: nil, name: m.name)
        case .image: return renderIcon(source: m.source, name: m.name)
        case .letter, .unset: return renderIcon(source: nil, name: m.name.isEmpty ? "?" : m.name)
        }
    }

    var validationError: String? {
        if trimmedName.isEmpty { return "请填写名称" }
        if URL(string: normalizedURL)?.host == nil { return "网址格式不对" }
        if store.nameTaken(trimmedName, except: original?.id) { return "已经有同名的网址了" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(original == nil ? "添加网址" : "编辑网址").font(.headline)
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 8) {
                    Image(nsImage: preview).resizable().interpolation(.high).frame(width: 96, height: 96)
                    if m.mode == .unset {
                        Text("保存时自动获取").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Form {
                    TextField("名称", text: $m.name, prompt: Text("Spotlight 里搜索用，如 Gmail"))
                    TextField("网址", text: $m.url, prompt: Text("https://…"))
                    HStack {
                        Button(m.fetching ? "获取中…" : "自动获取图标") { Task { await autoFetch() } }
                            .disabled(m.fetching || URL(string: normalizedURL)?.host == nil)
                        Button("选择图片…") { pickImage() }
                        Button("文字图标") { m.mode = .letter; m.source = nil; m.note = nil }
                    }
                    if let n = m.note { Text(n).font(.caption).foregroundStyle(.secondary) }
                }
                .formStyle(.columns)
            }
            HStack {
                if let e = validationError, !(trimmedName.isEmpty && m.url.isEmpty) {
                    Text(e).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button("取消", role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                Button("保存") { Task { await doSave() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationError != nil || m.fetching)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    func autoFetch() async {
        m.fetching = true
        defer { m.fetching = false }
        if let img = await fetchFavicon(page: normalizedURL) {
            m.source = img
            m.mode = .image
            m.note = pixelSize(img) >= 64 ? nil : "网站图标太小（\(pixelSize(img))px），已用它的主色生成文字图标"
        } else {
            m.mode = .letter
            m.note = "没取到网站图标，已用文字图标"
        }
    }

    func pickImage() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url, let img = NSImage(contentsOf: u) {
            m.source = img
            m.mode = .image
            m.note = nil
        }
    }

    func doSave() async {
        if m.mode == .unset { await autoFetch() }
        let icon: NSImage
        switch m.mode {
        case .existing: icon = preview
        case .image: icon = renderIcon(source: m.source, name: trimmedName)
        case .letter, .unset: icon = renderIcon(source: nil, name: trimmedName)
        }
        store.save(original: original, name: trimmedName, url: normalizedURL, icon: icon)
        close()
    }
}

// MARK: - 命令行（批量导入 / 重建）

func blocking(_ work: @escaping @Sendable () async -> Void) {
    let sem = DispatchSemaphore(value: 0)
    Task.detached { await work(); sem.signal() }
    sem.wait()
}

func cli() -> Bool {
    let a = CommandLine.arguments
    guard a.count >= 2 else { return false }
    switch a[1] {
    case "--import":   // --import 名称 网址 [现成图标PNG]
        guard a.count >= 4 else { print("用法: --import 名称 网址 [图标]"); exit(2) }
        let name = a[2], url = a[3], iconPath = a.count >= 5 ? a[4] : nil
        blocking {
            var links = loadLinks()
            let existing = links.first { safeAppName($0.name) == safeAppName(name) }
            let link = existing.map { var l = $0; l.url = url; return l }
                ?? WebLink(id: UUID().uuidString.lowercased(), name: name, url: url, appName: nil)
            let icon: NSImage
            if let iconPath, !iconPath.hasPrefix("src:"), let img = NSImage(contentsOfFile: iconPath) {
                icon = img
            } else {
                // src:路径 = 备选原图：和网站图标比，取像素更大的那张
                let alt = iconPath.flatMap { NSImage(contentsOfFile: String($0.dropFirst(4))) }
                let fav = await fetchFavicon(page: url)
                let pick = [fav, alt].compactMap { $0 }.max { pixelSize($0) < pixelSize($1) }
                print("  \(name): 网站图标 \(fav.map { "\(pixelSize($0))px" } ?? "无")，备选 \(alt.map { "\(pixelSize($0))px" } ?? "无")")
                icon = renderIcon(source: pick, name: name)
            }
            do {
                let updated = try installLink(link, icon: icon)
                if let i = links.firstIndex(where: { $0.id == updated.id }) { links[i] = updated } else { links.append(updated) }
                saveLinks(links)
                print("✓ \(name) → \(Paths.appsDir.appendingPathComponent(updated.appName ?? "").path)")
            } catch {
                print("✗ \(name): \(error.localizedDescription)")
            }
        }
        exit(0)
    case "--self-icon":   // --self-icon 输出PNG
        guard a.count >= 3 else { exit(2) }
        let img = renderIcon(source: nil, name: "网")
        try? pngData(img, size: 1024)?.write(to: URL(fileURLWithPath: a[2]))
        exit(0)
    default:
        return false
    }
}

@main
struct WebLinkManagerApp: App {
    @StateObject private var store: Store

    init() {
        _ = cli()
        _store = StateObject(wrappedValue: Store())
    }

    var body: some Scene {
        WindowGroup("网页快开") {
            ContentView().environmentObject(store)
        }
        .windowResizability(.contentMinSize)
    }
}
