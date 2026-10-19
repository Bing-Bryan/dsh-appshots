import ApplicationServices
import Carbon
import Cocoa
import CoreGraphics
import Foundation

let skipOwners: Set<String> = [
  "Dock",
  "Window Server",
  "Control Center",
  "Control Centre",
  "Notification Center",
  "Notification Centre",
  "Spotlight",
  "universalAccessAuthWarn",
  "SystemUIServer",
  "loginwindow",
  "Item-0",
  "Wallpaper",
  "WindowManager",
]

let leftCommandMask: UInt64 = 0x00000008
let rightCommandMask: UInt64 = 0x00000010
let rightOptionMask: UInt64 = 0x00000040

// The official DeepSeek Harness desktop app and the DSH Desktop shell.
let dshBundleIDs: Set<String> = [
  "com.deepseek.dsh",
  "ai.deepseek.dsh-desktop",
  "com.deepseek.dsh-desktop",
]
let dshAppNames: Set<String> = ["DeepSeek Harness", "DSH Desktop"]

func isDshApplication(_ app: NSRunningApplication) -> Bool {
  if let bundle = app.bundleIdentifier, dshBundleIDs.contains(bundle) { return true }
  if let name = app.localizedName, dshAppNames.contains(name) { return true }
  return false
}

func parentPid(of pid: pid_t) -> pid_t {
  var info = kinfo_proc()
  var size = MemoryLayout<kinfo_proc>.stride
  var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
  guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
  return info.kp_eproc.e_ppid
}

/// Resolve the GUI application that owns this helper by walking the parent
/// process chain. This keeps the plugin working for both the official
/// DeepSeek Harness app and third-party DSH Desktop shells.
func resolveHostApplication() -> NSRunningApplication? {
  var pid = getppid()
  var hops = 0
  while pid > 1 && hops < 16 {
    if let app = NSRunningApplication(processIdentifier: pid), isDshApplication(app) {
      return app
    }
    pid = parentPid(of: pid)
    hops += 1
  }
  return nil
}

func anyDshApplication() -> NSRunningApplication? {
  let apps = NSWorkspace.shared.runningApplications.filter(isDshApplication)
  return apps.first(where: { $0.isActive }) ?? apps.first
}

func emit(_ object: [String: Any]) {
  guard JSONSerialization.isValidJSONObject(object),
        let data = try? JSONSerialization.data(withJSONObject: object, options: []),
        let line = String(data: data, encoding: .utf8)
  else { return }
  fputs(line + "\n", stdout)
  fflush(stdout)
}

func fail(_ message: String) -> Never {
  emit(["ok": false, "error": message])
  exit(1)
}

func windowList() -> [[String: Any]] {
  let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
  return (CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]) ?? []
}

func windowArea(_ bounds: [String: Any]?) -> Double {
  let width = (bounds?["Width"] as? NSNumber)?.doubleValue ?? 0
  let height = (bounds?["Height"] as? NSNumber)?.doubleValue ?? 0
  return width * height
}

func isSkippableOwner(_ owner: String, extra: Set<String>) -> Bool {
  extra.contains(owner) || skipOwners.contains(owner)
}

func pickTargetWindow(skipOwners extra: Set<String>, skipPids: Set<pid_t> = []) -> (id: CGWindowID, owner: String, name: String, pid: pid_t)? {
  let windows = windowList().compactMap { info -> (id: CGWindowID, owner: String, name: String, pid: pid_t, area: Double)? in
    let layer = info[kCGWindowLayer as String] as? Int ?? -1
    guard layer == 0 else { return nil }
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    let name = info[kCGWindowName as String] as? String ?? ""
    let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? -1
    let id = CGWindowID(info[kCGWindowNumber as String] as? UInt32 ?? 0)
    let area = windowArea(info[kCGWindowBounds as String] as? [String: Any])
    guard id != 0, pid > 0, area >= 80 * 80, !skipPids.contains(pid) else { return nil }
    return (id, owner, name, pid, area)
  }

  func largest(for pid: pid_t) -> (id: CGWindowID, owner: String, name: String, pid: pid_t)? {
    windows.filter { $0.pid == pid }.max { $0.area < $1.area }.map { ($0.id, $0.owner, $0.name, $0.pid) }
  }

  if let front = NSWorkspace.shared.frontmostApplication {
    let owner = front.localizedName ?? ""
    if !isSkippableOwner(owner, extra: extra), !skipPids.contains(front.processIdentifier),
       let picked = largest(for: front.processIdentifier) {
      return picked
    }
  }

  var seen = Set<pid_t>()
  for window in windows {
    if isSkippableOwner(window.owner, extra: extra) { continue }
    if seen.contains(window.pid) { continue }
    seen.insert(window.pid)
    if let picked = largest(for: window.pid) { return picked }
  }
  return windows.max { $0.area < $1.area }.map { ($0.id, $0.owner, $0.name, $0.pid) }
}

func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
  if let text = value as? String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
  return nil
}

let skipRoles: Set<String> = [
  "AXMenuBar", "AXHelpTag",
  "AXColumn",
  "AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton",
]

let skipRoleDescriptions: Set<String> = [
  "关闭按钮", "缩放按钮", "最小化按钮", "全屏按钮", "全屏幕按钮", "进入全屏幕",
]

let chromeRoles: Set<String> = [
  "AXToolbar", "AXTabGroup",
]

func roleOf(_ element: AXUIElement) -> String {
  stringAttribute(element, kAXRoleAttribute as CFString) ?? ""
}

func boolAttribute(_ element: AXUIElement, _ name: CFString) -> Bool {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return false }
  if let flag = value as? Bool { return flag }
  if let number = value as? NSNumber { return number.boolValue }
  return false
}

func axElementList(_ element: AXUIElement, _ name: CFString) -> [AXUIElement] {
  var ref: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, name, &ref) == .success, let ref else { return [] }
  if let list = ref as? [AXUIElement] { return list }
  if CFGetTypeID(ref) == AXUIElementGetTypeID() { return [ref as! AXUIElement] }
  return []
}

struct AXID: Hashable {
  let element: AXUIElement
  func hash(into hasher: inout Hasher) {
    hasher.combine(CFHash(element))
  }
  static func == (lhs: AXID, rhs: AXID) -> Bool {
    CFEqual(lhs.element, rhs.element)
  }
}

func uniqueChildren(_ element: AXUIElement, _ names: [CFString]) -> [AXUIElement] {
  var seen = Set<AXID>()
  var out: [AXUIElement] = []
  for name in names {
    for child in axElementList(element, name) {
      if seen.insert(AXID(element: child)).inserted { out.append(child) }
    }
  }
  return out
}

func structuralChildren(_ element: AXUIElement) -> [AXUIElement] {
  let kids = uniqueChildren(element, [kAXChildrenAttribute as CFString])
  return kids.isEmpty ? uniqueChildren(element, [kAXVisibleChildrenAttribute as CFString]) : kids
}

func isContainerRole(_ role: String) -> Bool {
  ["AXGroup", "AXGenericElement", "AXUnknown", "AXScrollArea", "AXSplitter"].contains(role)
}

func isAttributeSettable(_ element: AXUIElement, _ name: CFString) -> Bool {
  var settable: DarwinBoolean = false
  guard AXUIElementIsAttributeSettable(element, name, &settable) == .success else { return false }
  return settable.boolValue
}

func compactURL(_ raw: String) -> String {
  var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  let folded = value.lowercased()
  for prefix in ["https://www.", "http://www.", "https://", "http://"] {
    if folded.hasPrefix(prefix) {
      value = String(value.dropFirst(prefix.count))
      break
    }
  }
  return value
}

func urlAttribute(_ element: AXUIElement) -> String? {
  var ref: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &ref) == .success, let ref else { return nil }
  if let url = ref as? URL { return compactURL(url.absoluteString) }
  if let text = ref as? String, !text.isEmpty { return compactURL(text) }
  return nil
}

let roleLabels: [String: String] = [
  "AXWindow": "标准窗口",
  "AXGroup": "container",
  "AXGenericElement": "container",
  "AXScrollArea": "container",
  "AXSplitter": "container",
  "AXWebArea": "HTML 内容",
  "AXButton": "按钮",
  "AXLink": "link",
  "AXStaticText": "文本",
  "AXUnknown": "container",
  "AXList": "内容列表",
  "AXHeading": "标题",
  "AXToolbar": "工具栏",
  "AXPopUpButton": "弹出式按钮",
  "AXTextField": "文本栏",
  "AXTextArea": "文本栏",
  "AXSearchField": "文本栏",
  "AXComboBox": "组合框",
  "AXCheckBox": "复选框",
  "AXRadioButton": "标签",
  "AXTabGroup": "标签组",
  "AXTab": "标签",
  "AXSeparator": "分离器",
  "AXImage": "图像",
  "AXDisclosureTriangle": "切换按钮",
  "AXMenuButton": "弹出式按钮",
  "AXRow": "row",
  "AXOutline": "外框",
  "AXSlider": "滑块",
  "AXCell": "单元格",
  "AXColumnHeader": "列标题",
  "AXTable": "表格",
  "AXColumn": "栏",
  "AXMenu": "菜单",
  "AXMenuItem": "",
]

func linkHasURL(_ element: AXUIElement) -> Bool {
  if let url = urlAttribute(element), !url.isEmpty { return true }
  if let value = stringAttribute(element, kAXValueAttribute as CFString), !value.isEmpty {
    let lower = value.lowercased()
    if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("chrome://") {
      return true
    }
    // Chrome often exposes path-style link values without scheme.
    if value.contains("/") || value.contains(".") { return true }
  }
  return false
}

func roleDescription(of element: AXUIElement) -> String {
  let role = roleOf(element)
  if role == "AXLink" {
    // Codex: URL-bearing web links → "link Description:, Value:";
    // named in-page links (e.g. 复制code) → "链接 …" with children.
    return linkHasURL(element) ? "link" : "链接"
  }
  if role == "AXSplitter" {
    let name = stringAttribute(element, kAXTitleAttribute as CFString)
      ?? stringAttribute(element, kAXDescriptionAttribute as CFString)
    if let name, !name.isEmpty {
      return "分离器"
    }
    return "container"
  }
  if ["AXGroup", "AXGenericElement", "AXScrollArea", "AXUnknown", "AXRow", "AXOutline", "AXSlider", "AXMenu", "AXMenuItem", "AXImage"].contains(role),
     let mapped = roleLabels[role] {
    return mapped
  }
  if let description = stringAttribute(element, kAXRoleDescriptionAttribute as CFString) {
    return description
  }
  return roleLabels[role] ?? role.replacingOccurrences(of: "AX", with: "")
}

func nodeIdentity(_ element: AXUIElement) -> (role: String, name: String?, description: String?, value: String?, url: String?, help: String?, placeholder: String?) {
  let role = roleOf(element)
  var title = stringAttribute(element, kAXTitleAttribute as CFString)
  let description = stringAttribute(element, kAXDescriptionAttribute as CFString)
  let help = stringAttribute(element, kAXHelpAttribute as CFString)
  let placeholder = stringAttribute(element, kAXPlaceholderValueAttribute as CFString)
  var value = stringAttribute(element, kAXValueAttribute as CFString)
  let url = urlAttribute(element)
  if title == nil, ["AXStaticText", "AXHeading"].contains(role), let staticValue = value {
    title = staticValue
    value = nil
  }
  let webStyleLink = role == "AXLink" && linkHasURL(element)
  let keepDescriptionField = ["AXLink", "AXSlider", "AXTab", "AXRadioButton", "AXTextField", "AXTextArea"].contains(role)
    && !(role == "AXLink" && !webStyleLink)
  var name = title
  let usableDescription = description.flatMap { text -> String? in
    if text.contains("要获取缺失的图片说明") || text.localizedCaseInsensitiveContains("to get missing") {
      return nil
    }
    return text
  }
  if name == nil, role == "AXLink", !webStyleLink, let usableDescription, !usableDescription.isEmpty {
    name = usableDescription
  } else if name == nil, !keepDescriptionField, let usableDescription, !usableDescription.isEmpty {
    name = usableDescription
  }
  let searchLike = role == "AXSearchField"
    || stringAttribute(element, kAXRoleDescriptionAttribute as CFString) == "搜索文本字段"
  if searchLike, let placeholder, !placeholder.isEmpty {
    name = placeholder
  }
  var resolvedURL = url
  if role == "AXWindow", resolvedURL == nil {
    resolvedURL = firstWebAreaURL(element)
  }
  if name == nil, ["AXWebArea", "AXDocument"].contains(role), let webURL = resolvedURL {
    name = webURL
    resolvedURL = nil
  }
  return (role, name, description, value, resolvedURL, help, placeholder)
}

func nodeLine(_ element: AXUIElement) -> String {
  let ident = nodeIdentity(element)
  let role = ident.role
  let roleDesc = roleDescription(of: element)
  let editableRoles = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXTab", "AXRadioButton"]
  let booleanRoles = ["AXRadioButton", "AXTab"]
  let rawValue = (ident.value ?? "").lowercased()
  let booleanValue = ["on", "off", "0", "1", "true", "false"].contains(rawValue)
  var states: [String] = []
  if boolAttribute(element, kAXSelectedAttribute as CFString) { states.append("selected") }
  let settable = editableRoles.contains(role) && isAttributeSettable(element, kAXValueAttribute as CFString)
  if settable { states.append("settable") }
  if settable && (booleanRoles.contains(role) || booleanValue) { states.append("boolean") }

  var head = roleDesc
  if !states.isEmpty {
    head += " (\(states.joined(separator: ", ")))"
  }
  if let name = ident.name, !name.isEmpty {
    head += head.isEmpty ? name : " \(name)"
  }

  var extras: [String] = []
  let noisyDescription = (ident.description ?? "").contains("要获取缺失的图片说明")
    || (ident.description ?? "").localizedCaseInsensitiveContains("to get missing")
  let usedDescriptionAsName = ident.name != nil && ident.name == ident.description && ident.name != stringAttribute(element, kAXTitleAttribute as CFString)
  if let description = ident.description, description != ident.name, !usedDescriptionAsName, !noisyDescription {
    extras.append("Description: \(description)")
  }
  if booleanRoles.contains(role) || roleDesc == "标签" {
    if let value = ident.value, booleanValue {
      extras.append("Value: \(normalizeBooleanValue(value))")
    } else if !extras.contains(where: { $0.hasPrefix("Value:") }) {
      extras.append("Value: \(states.contains("selected") ? "on" : "off")")
    }
  } else if let value = ident.value, !value.isEmpty, value != ident.name, value != ident.description {
    if role == "AXWebArea" || role == "AXDocument" {
      // Keep the tree; the page body lives in child nodes.
    } else if value.count <= 800 {
      extras.append("Value: \(compactURL(value))")
    }
  }
  if let placeholder = ident.placeholder, placeholder != ident.name {
    extras.append("Placeholder: \(placeholder)")
  }
  if let help = ident.help, help != ident.name, help != ident.description {
    extras.append("Help: \(help)")
  }
  if let url = ident.url {
    if role == "AXLink" && !extras.contains(where: { $0.hasPrefix("Value:") }) {
      extras.append("Value: \(url)")
    } else if role != "AXLink" {
      extras.append("URL: \(url)")
    }
  }
  func oneLine(_ value: String) -> String {
    value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }
  if extras.isEmpty { return oneLine(head) }
  if ident.name == nil {
    return oneLine("\(head) \(extras.joined(separator: ", "))")
  }
  return oneLine("\(head), \(extras.joined(separator: ", "))")
}

func shouldSkipDuplicateChild(_ parent: AXUIElement, _ child: AXUIElement) -> Bool {
  guard roleOf(child) == "AXStaticText" else { return false }
  let parentRole = roleOf(parent)
  let childIdent = nodeIdentity(child)
  if (childIdent.name ?? "").isEmpty { return true }
  if ["AXHeading", "AXMenuItem", "AXButton"].contains(parentRole) { return false }
  let parentIdent = nodeIdentity(parent)
  guard let childName = childIdent.name, !childName.isEmpty else { return false }
  return childName == parentIdent.name || childName == parentIdent.description
}

func isUnlabeled(_ element: AXUIElement) -> Bool {
  let ident = nodeIdentity(element)
  let named = ident.name?.isEmpty == false
  let described = ident.description?.isEmpty == false
  let valued = ident.value?.isEmpty == false
  let urled = ident.url?.isEmpty == false
  let helped = ident.help?.isEmpty == false
  return !named && !described && !valued && !urled && !helped
}

func normalizeBooleanValue(_ value: String) -> String {
  switch value.lowercased() {
  case "1", "true", "on": return "on"
  case "0", "false", "off": return "off"
  default: return value
  }
}

func firstWebAreaURL(_ element: AXUIElement, depth: Int = 0) -> String? {
  if depth > 8 { return nil }
  if ["AXWebArea", "AXDocument"].contains(roleOf(element)), let url = urlAttribute(element) {
    return url
  }
  for child in structuralChildren(element).prefix(30) {
    if let url = firstWebAreaURL(child, depth: depth + 1) { return url }
  }
  return nil
}

func markdownLink(_ element: AXUIElement) -> String? {
  guard roleOf(element) == "AXLink" else { return nil }
  let ident = nodeIdentity(element)
  let label = ident.description ?? ident.name ?? ""
  let href = ident.value ?? ident.url ?? ""
  guard !label.isEmpty, !href.isEmpty else { return nil }
  return "[\(label)](\(href))"
}

func isSkippedNode(_ element: AXUIElement) -> Bool {
  let role = roleOf(element)
  if skipRoles.contains(role) { return true }
  if let roleDesc = stringAttribute(element, kAXRoleDescriptionAttribute as CFString),
     skipRoleDescriptions.contains(roleDesc) {
    return true
  }
  if boolAttribute(element, kAXHiddenAttribute as CFString) { return true }
  return false
}

func meaningfulChildren(_ element: AXUIElement) -> [AXUIElement] {
  var out: [AXUIElement] = []
  for child in structuralChildren(element) {
    if isSkippedNode(child) { continue }
    if isContainerRole(roleOf(child)), isUnlabeled(child), meaningfulChildren(child).isEmpty {
      continue
    }
    out.append(child)
  }
  return out
}

func unwrapMenuItems(_ element: AXUIElement) -> [AXUIElement] {
  var items: [AXUIElement] = []
  for child in meaningfulChildren(element) {
    let role = roleOf(child)
    if role == "AXMenuItem" {
      items.append(child)
    } else if isContainerRole(role), isUnlabeled(child) {
      items.append(contentsOf: unwrapMenuItems(child))
    }
  }
  return items
}

func menuItemHasSubmenu(_ item: AXUIElement) -> Bool {
  func walk(_ element: AXUIElement) -> Bool {
    for child in structuralChildren(element) {
      if isSkippedNode(child) { continue }
      let role = roleOf(child)
      if role == "AXMenu" { return true }
      if isContainerRole(role), isUnlabeled(child), walk(child) { return true }
    }
    return false
  }
  return walk(item)
}

func isUnlabeledWrapper(_ element: AXUIElement, kids: [AXUIElement]) -> Bool {
  isContainerRole(roleOf(element)) && isUnlabeled(element) && kids.count <= 1
}

func expandedKids(_ element: AXUIElement) -> [AXUIElement] {
  var out: [AXUIElement] = []
  for child in meaningfulChildren(element) {
    let childKids = meaningfulChildren(child)
    if isUnlabeledWrapper(child, kids: childKids) {
      out.append(contentsOf: expandedKids(child))
    } else {
      out.append(child)
    }
  }
  return out
}

func itemHasDirectLink(_ item: AXUIElement) -> Bool {
  for child in structuralChildren(item) {
    if isSkippedNode(child) { continue }
    let role = roleOf(child)
    if role == "AXMenu" { continue }
    if role == "AXLink" { return true }
    if isContainerRole(role), isUnlabeled(child), itemHasDirectLink(child) { return true }
  }
  return false
}

func isLeafyMenu(_ menu: AXUIElement) -> Bool {
  let items = unwrapMenuItems(menu)
  if items.isEmpty { return false }
  let linked = items.filter(itemHasDirectLink).count
  return linked >= 1 && linked * 2 >= items.count
}

func shouldHoistMenu(_ element: AXUIElement, parentRole: String, inLeafMenu: Bool) -> Bool {
  guard roleOf(element) == "AXMenu", isUnlabeled(element) else { return false }
  // Grouping menus (no/few direct links): flatten under both menu and menu-item parents.
  // Codex keeps only leafy menus (AI问答…); section menus under 丁香医考 are flattened.
  if !isLeafyMenu(element) {
    return parentRole == "AXMenu" || parentRole == "AXMenuItem"
  }
  // Nested leafy menus inside an already-leafy menu (e.g. 医考crm) are flattened.
  return parentRole == "AXMenuItem" && inLeafMenu
}

func chromeFingerprint(_ element: AXUIElement) -> String? {
  let role = roleOf(element)
  let ident = nodeIdentity(element)
  let name = ident.name ?? ""
  if chromeRoles.contains(role) {
    return "\(role)|\(name)"
  }
  if ["标签页搜索", "新标签页", "打开 Chrome 中的 Gemini"].contains(name) {
    return "\(role)|\(name)"
  }
  return nil
}

func dumpTree(
  _ element: AXUIElement,
  depth: Int,
  deadline: Date,
  budget: inout Int,
  into lines: inout [String],
  seenChrome: inout Set<String>,
  seenElements: inout Set<AXID>,
  parentRole: String = "",
  inLeafMenu: Bool = false
) {
  if Date() > deadline || budget <= 0 { return }
  let role = roleOf(element)
  if skipRoles.contains(role) { return }
  if let roleDesc = stringAttribute(element, kAXRoleDescriptionAttribute as CFString),
     skipRoleDescriptions.contains(roleDesc) {
    return
  }
  if boolAttribute(element, kAXHiddenAttribute as CFString) { return }
  if !seenElements.insert(AXID(element: element)).inserted { return }
  if let key = chromeFingerprint(element), !seenChrome.insert(key).inserted { return }
  let kids = expandedKids(element)
  if isContainerRole(role), isUnlabeled(element), kids.isEmpty { return }
  if shouldHoistMenu(element, parentRole: parentRole, inLeafMenu: inLeafMenu) {
    for child in kids.prefix(400) {
      dumpTree(
        child,
        depth: depth,
        deadline: deadline,
        budget: &budget,
        into: &lines,
        seenChrome: &seenChrome,
        seenElements: &seenElements,
        parentRole: parentRole,
        inLeafMenu: inLeafMenu
      )
    }
    return
  }
  budget -= 1
  let indent = String(repeating: "\t", count: depth)
  lines.append(indent + nodeLine(element))
  // Codex keeps URL-bearing web links collapsed; expand named 「链接」 (e.g. 复制code).
  if role == "AXLink", linkHasURL(element) {
    return
  }
  var index = 0
  let limitedKids = Array(kids.prefix(400))
  while index < limitedKids.count {
    let child = limitedKids[index]
    if shouldSkipDuplicateChild(element, child) {
      index += 1
      continue
    }
    if role == "AXTable" {
      let childRole = roleOf(child)
      if childRole == "AXColumnHeader" || childRole == "AXColumn" {
        index += 1
        continue
      }
      if isContainerRole(childRole), isUnlabeled(child), expandedKids(child).isEmpty {
        index += 1
        continue
      }
    }
    if roleOf(child) == "AXStaticText",
       let textName = nodeIdentity(child).name, !textName.isEmpty {
      if index + 1 < limitedKids.count,
         roleOf(limitedKids[index + 1]) == "AXStaticText",
         nodeIdentity(limitedKids[index + 1]).name == ":" {
        lines.append(String(repeating: "\t", count: depth + 1) + "text \(textName) :")
        _ = seenElements.insert(AXID(element: limitedKids[index + 1]))
        index += 2
        continue
      }
      if index + 1 < limitedKids.count,
         let md = markdownLink(limitedKids[index + 1]) {
        lines.append(String(repeating: "\t", count: depth + 1) + "text \(textName) \(md)")
        _ = seenElements.insert(AXID(element: limitedKids[index + 1]))
        index += 2
        continue
      }
    }
    let siblingMenu = role == "AXMenuItem"
      && roleOf(child) == "AXMenu"
      && isUnlabeled(child)
    dumpTree(
      child,
      depth: siblingMenu ? depth : depth + 1,
      deadline: deadline,
      budget: &budget,
      into: &lines,
      seenChrome: &seenChrome,
      seenElements: &seenElements,
      parentRole: role,
      inLeafMenu: inLeafMenu || (role == "AXMenu" && isLeafyMenu(element))
    )
    index += 1
  }
}

func windowRoot(app: AXUIElement, windowName: String) -> AXUIElement {
  AXUIElementSetMessagingTimeout(app, 3.0)
  var focused: CFTypeRef?
  if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
     let focused,
     CFGetTypeID(focused) == AXUIElementGetTypeID() {
    return focused as! AXUIElement
  }
  let windows = axElementList(app, kAXWindowsAttribute as CFString)
  if !windowName.isEmpty,
     let match = windows.first(where: { stringAttribute($0, kAXTitleAttribute as CFString) == windowName }) {
    return match
  }
  return windows.first ?? app
}

func describeFocused(_ element: AXUIElement) -> String {
  var parts = [nodeLine(element)]
  if let url = urlAttribute(element) {
    if !parts[0].contains("URL:") {
      parts[0] += ", URL: \(url)"
    }
  }
  return parts[0]
}

func focusedElement(from candidates: [AXUIElement]) -> AXUIElement? {
  for candidate in candidates {
    var focusedRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(candidate, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
       let focusedRef,
       CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
      let focusedElement = focusedRef as! AXUIElement
      let focusedRole = roleOf(focusedElement)
      if focusedRole != "AXWindow", focusedRole != "AXApplication", !focusedRole.isEmpty {
        return focusedElement
      }
    }
  }
  return nil
}

func windowText(pid: pid_t, owner: String, windowName: String, maxChars: Int) -> (text: String, truncated: Bool, trusted: Bool) {
  _ = owner
  let trusted = AXIsProcessTrusted()
  guard trusted else { return ("", false, false) }
  let app = AXUIElementCreateApplication(pid)
  let root = windowRoot(app: app, windowName: windowName)
  var lines: [String] = []
  let deadline = Date().addingTimeInterval(6.0)
  var budget = 25000
  var seenChrome = Set<String>()
  var seenElements = Set<AXID>()
  dumpTree(
    root,
    depth: 0,
    deadline: deadline,
    budget: &budget,
    into: &lines,
    seenChrome: &seenChrome,
    seenElements: &seenElements
  )
  var focusedLabel = ""
  if let focused = focusedElement(from: [root, app]) {
    focusedLabel = describeFocused(focused)
  }
  var text = lines.joined(separator: "\n")
  if !focusedLabel.isEmpty {
    text += "\n\nThe focused UI element is \(focusedLabel)"
  }
  if text.count > maxChars {
    let end = text.index(text.startIndex, offsetBy: maxChars)
    return (String(text[..<end]), true, true)
  }
  return (text, false, true)
}

func activateDshDesktop() -> [String: Any] {
  guard let target = resolveHostApplication() ?? anyDshApplication() else {
    return ["app": "", "pid": 0, "reason": "no-host-app"]
  }
  if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
    return ["app": target.localizedName ?? "", "pid": Int(target.processIdentifier), "alreadyFrontmost": true]
  }
  // Never mutate the Host through Accessibility here: an AX frontmost write can
  // deadlock a busy Host and leave the whole turn hanging. LaunchServices
  // activation is best-effort and safe.
  let activated: Bool
  if #available(macOS 14.0, *) {
    activated = target.activate(options: [.activateAllWindows])
  } else {
    activated = target.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
  }
  return [
    "app": target.localizedName ?? "",
    "pid": Int(target.processIdentifier),
    "activated": activated,
  ]
}

func playShutterSound() {
  let paths = [
    "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif",
    "/System/Library/Sounds/Pop.aiff",
  ]
  guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
  process.arguments = ["-v", "0.7", path]
  do { try process.run() } catch {}
}

func windowQuartzFrame(_ windowId: CGWindowID) -> CGRect? {
  let options: CGWindowListOption = [.optionIncludingWindow]
  guard let list = CGWindowListCopyWindowInfo(options, windowId) as? [[String: Any]],
        let info = list.first,
        let bounds = info[kCGWindowBounds as String] as? [String: Any],
        let x = bounds["X"] as? NSNumber,
        let y = bounds["Y"] as? NSNumber,
        let width = bounds["Width"] as? NSNumber,
        let height = bounds["Height"] as? NSNumber,
        width.doubleValue > 1,
        height.doubleValue > 1
  else { return nil }
  return CGRect(x: x.doubleValue, y: y.doubleValue, width: width.doubleValue, height: height.doubleValue)
}

func showWindowOutline(windowId: CGWindowID) {
  guard let quartz = windowQuartzFrame(windowId),
        let primary = NSScreen.screens.first
  else { return }
  let rect = CGRect(
    x: quartz.origin.x,
    y: primary.frame.height - quartz.origin.y - quartz.height,
    width: quartz.width,
    height: quartz.height
  ).insetBy(dx: -2, dy: -2)
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let window = NSWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
  window.isOpaque = false
  window.backgroundColor = .clear
  window.hasShadow = false
  window.ignoresMouseEvents = true
  window.level = .floating
  window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
  let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
  view.wantsLayer = true
  let accent = NSColor(calibratedRed: 0.42, green: 0.44, blue: 1.0, alpha: 1.0)
  view.layer?.backgroundColor = NSColor.clear.cgColor
  view.layer?.cornerRadius = 12
  view.layer?.borderWidth = 3
  view.layer?.borderColor = accent.cgColor
  view.layer?.shadowColor = accent.cgColor
  view.layer?.shadowOpacity = 0.85
  view.layer?.shadowRadius = 16
  view.layer?.shadowOffset = .zero
  window.contentView = view
  window.alphaValue = 0
  window.orderFrontRegardless()
  NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.08
    window.animator().alphaValue = 1
  }
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
    NSAnimationContext.runAnimationGroup({ context in
      context.duration = 0.22
      window.animator().alphaValue = 0
    }, completionHandler: {
      window.close()
      NSApp.terminate(nil)
    })
  }
  app.run()
}

func selfSkipPid() -> Set<pid_t> {
  guard let app = resolveHostApplication() else { return [] }
  return [app.processIdentifier]
}

func extraSkip(skipSelf: Bool) -> Set<String> {
  guard skipSelf, let app = resolveHostApplication(), let name = app.localizedName else { return [] }
  return [name]
}

func frontPayload(skipSelf: Bool, maxChars: Int) -> [String: Any] {
  let skipPids = skipSelf ? selfSkipPid() : []
  guard let target = pickTargetWindow(skipOwners: extraSkip(skipSelf: skipSelf), skipPids: skipPids) else {
    return ["ok": false, "error": "no on-screen window to capture"]
  }
  let extracted = windowText(pid: target.pid, owner: target.owner, windowName: target.name, maxChars: maxChars)
  return [
    "ok": true,
    "owner": target.owner,
    "title": target.name,
    "pid": Int(target.pid),
    "windowId": Int(target.id),
    "text": extracted.text,
    "textTruncated": extracted.truncated,
    "axTrusted": extracted.trusted,
  ]
}

func status() {
  let extras = extraSkip(skipSelf: true)
  let skipPids = selfSkipPid()
  let target = pickTargetWindow(skipOwners: extras, skipPids: skipPids)
  let host = resolveHostApplication()
  let namesPresent = windowList().contains { info in
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    let name = info[kCGWindowName as String] as? String ?? ""
    return !isSkippableOwner(owner, extra: extras) && !name.isEmpty
  }
  emit([
    "ok": true,
    "axTrusted": AXIsProcessTrusted(),
    "windowNamesVisible": namesPresent,
    "frontOwner": target?.owner ?? "",
    "frontTitle": target?.name ?? "",
    "hostApp": host?.localizedName ?? "",
    "hostBundle": host?.bundleIdentifier ?? "",
    "hostPid": host.map { Int($0.processIdentifier) } ?? 0,
  ])
}

func promptAccessibilityIfNeeded() {
  if AXIsProcessTrusted() { return }
  let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
  _ = AXIsProcessTrustedWithOptions(options)
}

func runCarbonHotkey(keyCode: UInt32, modifiers: UInt32) {
  var hotKeyRef: EventHotKeyRef?
  var handlerRef: EventHandlerRef?
  let hotKeyID = EventHotKeyID(signature: OSType(0x41505348), id: 1)
  var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
  let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    emit(["event": "hotkey"])
    return noErr
  }, 1, &eventType, nil, &handlerRef)
  guard status == noErr else { fail("failed to install hotkey handler (\(status))") }
  let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
  guard registered == noErr else { fail("failed to register hotkey (\(registered)). It may already be in use.") }
  emit(["event": "ready", "mode": "carbon", "keyCode": Int(keyCode), "modifiers": Int(modifiers)])
  RunLoop.main.run()
}

private var hotkeyArmed = true
private var hotkeyTap: CFMachPort?
private var activeHotkeyMode = "both-command"
private var rightCommandDown = false
private var swallowSpaceUp = false
private var lastHotkeyFire = Date.distantPast
private var lastRightCommandTap = Date.distantPast
private var rightCommandDownAt = Date.distantPast
private var rightCommandDirty = false
private var rightCommandFired = false

func fireHotkey() {
  let now = Date()
  guard now.timeIntervalSince(lastHotkeyFire) > 0.35 else { return }
  lastHotkeyFire = now
  emit(["event": "hotkey"])
}

func hotkeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
  if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    if let tap = hotkeyTap {
      CGEvent.tapEnable(tap: tap, enable: true)
    }
    return Unmanaged.passUnretained(event)
  }
  let flags = event.flags.rawValue
  switch activeHotkeyMode {
  case "right-command-right-option":
    if type == .flagsChanged {
      let rightCommand = (flags & rightCommandMask) != 0
      let rightOption = (flags & rightOptionMask) != 0
      if rightCommand && rightOption {
        if hotkeyArmed {
          hotkeyArmed = false
          fireHotkey()
        }
      } else {
        hotkeyArmed = true
      }
    }
  case "double-right-command":
    if type == .flagsChanged {
      let right = (flags & rightCommandMask) != 0
      let otherModifiers = (flags & (
        leftCommandMask
          | rightOptionMask
          | CGEventFlags.maskShift.rawValue
          | CGEventFlags.maskControl.rawValue
          | CGEventFlags.maskAlternate.rawValue
      )) != 0
      if right && !rightCommandDown {
        rightCommandDown = true
        rightCommandDownAt = Date()
        rightCommandDirty = false
        rightCommandFired = false
        if !otherModifiers {
          let gap = Date().timeIntervalSince(lastRightCommandTap)
          if gap > 0 && gap < 0.42 {
            lastRightCommandTap = .distantPast
            rightCommandFired = true
            fireHotkey()
          }
        } else {
          lastRightCommandTap = .distantPast
        }
      } else if !right && rightCommandDown {
        rightCommandDown = false
        let held = Date().timeIntervalSince(rightCommandDownAt)
        if !rightCommandDirty && !rightCommandFired && !otherModifiers && held < 0.5 {
          lastRightCommandTap = Date()
        } else {
          lastRightCommandTap = .distantPast
        }
      }
    } else if type == .keyDown && rightCommandDown {
      rightCommandDirty = true
    }
  case "space-right-command":
    if type == .flagsChanged {
      rightCommandDown = (flags & rightCommandMask) != 0
      if !rightCommandDown { swallowSpaceUp = false }
    } else if type == .keyDown {
      let code = event.getIntegerValueField(.keyboardEventKeycode)
      if code == 49 && rightCommandDown {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if !isRepeat { fireHotkey() }
        swallowSpaceUp = true
        return nil
      }
    } else if type == .keyUp {
      let code = event.getIntegerValueField(.keyboardEventKeycode)
      if code == 49 && swallowSpaceUp {
        swallowSpaceUp = false
        return nil
      }
    }
  default:
    if type == .flagsChanged {
      let left = (flags & leftCommandMask) != 0
      let right = (flags & rightCommandMask) != 0
      if left && right {
        if hotkeyArmed {
          hotkeyArmed = false
          fireHotkey()
        }
      } else {
        hotkeyArmed = true
      }
    }
  }
  return Unmanaged.passUnretained(event)
}

func runHotkey(mode: String) {
  promptAccessibilityIfNeeded()
  activeHotkeyMode = mode
  hotkeyArmed = true
  rightCommandDown = false
  swallowSpaceUp = false
  lastRightCommandTap = .distantPast
  rightCommandDownAt = .distantPast
  rightCommandDirty = false
  rightCommandFired = false
  var mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
  if mode == "space-right-command" {
    mask |= CGEventMask(1 << CGEventType.keyDown.rawValue)
    mask |= CGEventMask(1 << CGEventType.keyUp.rawValue)
  }
  if mode == "double-right-command" {
    mask |= CGEventMask(1 << CGEventType.keyDown.rawValue)
  }
  guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: mode == "space-right-command" ? .defaultTap : .listenOnly,
    eventsOfInterest: mask,
    callback: hotkeyTapCallback,
    userInfo: nil
  ) else {
    fail("failed to create event tap. Grant Accessibility to DeepSeek Harness and appshot-capture.")
  }
  hotkeyTap = tap
  let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
  CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
  CGEvent.tapEnable(tap: tap, enable: true)
  emit(["event": "ready", "mode": mode])
  CFRunLoopRun()
}

func argValue(_ name: String) -> String? {
  guard let index = CommandLine.arguments.firstIndex(of: name),
        index + 1 < CommandLine.arguments.count
  else { return nil }
  return CommandLine.arguments[index + 1]
}

func hasFlag(_ name: String) -> Bool {
  CommandLine.arguments.contains(name)
}

let command = CommandLine.arguments.dropFirst().first ?? "front"
let skipSelf = !hasFlag("--include-self")
let maxChars = Int(argValue("--max-chars") ?? "80000") ?? 80_000

switch command {
case "front":
  promptAccessibilityIfNeeded()
  let payload = frontPayload(skipSelf: skipSelf, maxChars: maxChars)
  emit(payload)
  if payload["ok"] as? Bool == true {
    if !hasFlag("--silent") {
      playShutterSound()
    }
    if let windowId = payload["windowId"] as? Int, windowId > 0, !hasFlag("--no-outline") {
      showWindowOutline(windowId: CGWindowID(windowId))
    }
  }
  if payload["ok"] as? Bool != true { exit(1) }
case "pidtext":
  let targetPid = pid_t(argValue("--pid") ?? "0") ?? 0
  guard targetPid > 0 else { fail("missing --pid") }
  let extracted = windowText(pid: targetPid, owner: "", windowName: argValue("--title") ?? "", maxChars: maxChars)
  emit([
    "ok": true,
    "pid": Int(targetPid),
    "text": extracted.text,
    "textTruncated": extracted.truncated,
    "axTrusted": extracted.trusted,
  ])
case "activate":
  emit(["ok": true, "event": "activated", "target": activateDshDesktop()])
case "status":
  promptAccessibilityIfNeeded()
  status()
case "hotkey":
  let mode = argValue("--mode") ?? "double-right-command"
  if mode == "carbon" {
    let keyCode = UInt32(argValue("--key-code") ?? "0") ?? 0
    let modifiers = UInt32(argValue("--modifiers") ?? "768") ?? 768
    runCarbonHotkey(keyCode: keyCode, modifiers: modifiers)
  } else {
    runHotkey(mode: mode)
  }
default:
  fail("unknown command \(command)")
}
