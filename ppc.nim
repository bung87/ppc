## PowerPlanSwitcher - Windows 系统托盘电源计划切换工具
##
## 功能：
##   - 系统托盘图标 + 右键菜单，切换 Windows 电源计划
##   - 菜单中可勾选「开机自启动」（写入注册表 Run 键）
##
## 依赖：winim（Windows API 绑定）。
## 电源计划通过 powrprof.dll 的电源管理 API 读取/切换，
## 不依赖 powercfg 子进程，无控制台编码问题。

import winim/lean
import winim/inc/shellapi    # Shell_NotifyIconW / NOTIFYICONDATAW
import winim/inc/powrprof    # 电源管理 API（PowerEnumerate 等）
import std/[os, strutils]

const
  AppTitle = "电源计划切换"
  WmTrayCallback = UINT(WM_APP + 0x100)  # 托盘图标回调消息
  IdTrayIcon = 1
  CmdBase = 1000                    # 电源计划菜单项 id = CmdBase + 序号
  CmdAutoStart = 2001
  CmdExit = 2002
  RegRunKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Run"
  RegValueName = "PowerPlanSwitcher"

type
  PowerPlan = object
    guid: GUID
    name: string

var
  gHwnd: HWND
  gIcon: HICON
  gTaskbarCreated: UINT = 0         # "TaskbarCreated" 注册消息（任务栏重启后重建图标）

# ---------------------------------------------------------------------------
# 电源计划：powrprof.dll API
# ---------------------------------------------------------------------------

proc enumPlans(): seq[PowerPlan] =
  ## 枚举系统所有电源计划及友好名称（UTF-16 直接转换，无乱码问题）。
  var index: ULONG = 0
  while true:
    var guid: GUID
    var size = DWORD sizeof(guid)
    let err = PowerEnumerate(cast[HKEY](nil), nil, nil, ACCESS_SCHEME, index,
      cast[ptr UCHAR](&guid), &size)
    if err != ERROR_SUCCESS:  # ERROR_NO_MORE_ITEMS 结束枚举
      break
    var nameBuf: array[256, WCHAR]
    var nameSize = DWORD sizeof(nameBuf)
    var name = ""
    if PowerReadFriendlyName(cast[HKEY](nil), &guid, nil, nil,
        cast[PUCHAR](&nameBuf), &nameSize) == ERROR_SUCCESS:
      name = nullTerminated($cast[ptr WCHAR](&nameBuf))
    if name.len == 0:
      name = "计划 " & $index
    result.add PowerPlan(guid: guid, name: name)
    inc index

proc activePlanGuid(): GUID =
  ## 查询当前激活的电源计划 GUID。
  var p: ptr GUID
  if PowerGetActiveScheme(cast[HKEY](nil), &p) == ERROR_SUCCESS and p != nil:
    result = p[]
    discard LocalFree(cast[HLOCAL](p))

proc setActivePlan(guid: ptr GUID): bool =
  PowerSetActiveScheme(cast[HKEY](nil), guid) == ERROR_SUCCESS

# ---------------------------------------------------------------------------
# 开机自启动：注册表 HKCU\...\CurrentVersion\Run
# ---------------------------------------------------------------------------

proc isAutoStartEnabled(): bool =
  var hkey: HKEY
  if RegOpenKeyExW(HKEY_CURRENT_USER, T(RegRunKey), 0, KEY_READ, &hkey) != ERROR_SUCCESS:
    return false
  var
    buf: array[1024, WCHAR]
    size = DWORD sizeof(buf)
  let res = RegQueryValueExW(hkey, T(RegValueName), nil, nil,
    cast[ptr BYTE](&buf), &size)
  RegCloseKey(hkey)
  if res != ERROR_SUCCESS:
    return false
  # 值存在且指向当前程序才认为已启用
  let value = nullTerminated($cast[ptr WCHAR](&buf))
  return value.contains(getAppFilename())

proc setAutoStart(enabled: bool) =
  var hkey: HKEY
  if RegCreateKeyExW(HKEY_CURRENT_USER, T(RegRunKey), 0, nil,
      REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nil, &hkey, nil) != ERROR_SUCCESS:
    return
  if enabled:
    let path = "\"" & getAppFilename() & "\""
    let pathW = T(path)
    discard RegSetValueExW(hkey, T(RegValueName), 0, REG_SZ,
      cast[ptr BYTE](&pathW), DWORD (pathW.len + 1) * 2)
  else:
    discard RegDeleteValueW(hkey, T(RegValueName))
  RegCloseKey(hkey)

# ---------------------------------------------------------------------------
# 托盘图标：GDI 程序内绘制 32x32（蓝底圆 + 白色 P 字）
# ---------------------------------------------------------------------------

proc makeTrayIcon(): HICON =
  const Sz = 32
  let screenDC = GetDC(0)

  # 32 位 ARGB 自顶向下 DIB：透明由 alpha 通道表达，不依赖单色蒙版
  # （单品位图绘制在「画笔颜色 == 背景色时输出 0」，极易踩坑）。
  # GDI 绘图不写 alpha（保持 0），绘制完成后在内存里逐像素修正。
  var bmi: BITMAPINFO
  bmi.bmiHeader = BITMAPINFOHEADER(
    biSize: DWORD sizeof(BITMAPINFOHEADER),
    biWidth: LONG Sz,
    biHeight: LONG -Sz,
    biPlanes: 1,
    biBitCount: 32,
    biCompression: DWORD BI_RGB)
  var bits: pointer
  let colorBmp = CreateDIBSection(screenDC, &bmi, DIB_RGB_COLORS, &bits,
    cast[HANDLE](nil), 0)
  let memDC = CreateCompatibleDC(screenDC)
  discard SelectObject(memDC, colorBmp)

  # 整幅先填黑（圆外颜色）
  var fullRc = RECT(left: 0, top: 0, right: Sz, bottom: Sz)
  discard FillRect(memDC, &fullRc, HBRUSH(GetStockObject(BLACK_BRUSH)))
  # 蓝色圆 + 白色 P
  let brush = CreateSolidBrush(RGB(0x1E, 0x6B, 0xC8))
  discard SelectObject(memDC, brush)
  Ellipse(memDC, 0, 0, Sz, Sz)
  let font = CreateFontW(-20, 0, 0, 0, FW_BOLD, 0, 0, 0,
    DEFAULT_CHARSET, 0, 0, 0, 0, T("Arial"))
  discard SelectObject(memDC, font)
  SetTextColor(memDC, RGB(0xFF, 0xFF, 0xFF))
  SetBkMode(memDC, TRANSPARENT)
  var rc = RECT(left: 0, top: 0, right: Sz, bottom: Sz)
  DrawTextW(memDC, T("P"), -1, &rc, DT_CENTER or DT_VCENTER or DT_SINGLELINE)

  GdiFlush()

  # 逐像素写 alpha：圆内 255，圆外 0
  let px = cast[ptr array[Sz * Sz, uint32]](bits)
  for y in 0 ..< Sz:
    for x in 0 ..< Sz:
      let dx = float(x - (Sz div 2))
      let dy = float(y - (Sz div 2))
      if dx * dx + dy * dy <= float((Sz div 2) * (Sz div 2)):
        px[y * Sz + x] = px[y * Sz + x] or 0xFF000000'u32
      else:
        px[y * Sz + x] = px[y * Sz + x] and 0x00FFFFFF'u32

  # alpha 图标仍要求提供蒙版位图：给一幅全黑（全 0 = AND 不作用），
  # 实际透明由 32 位位图的 alpha 通道决定
  let maskDC = CreateCompatibleDC(screenDC)
  let maskBmp = CreateBitmap(Sz, Sz, 1, 1, nil)
  discard SelectObject(maskDC, maskBmp)
  discard FillRect(maskDC, &fullRc, HBRUSH(GetStockObject(BLACK_BRUSH)))

  var info = ICONINFO(fIcon: TRUE, hbmMask: maskBmp, hbmColor: colorBmp)
  result = CreateIconIndirect(&info)

  DeleteDC(memDC)
  DeleteDC(maskDC)
  DeleteObject(colorBmp)
  DeleteObject(maskBmp)
  DeleteObject(brush)
  DeleteObject(font)
  ReleaseDC(0, screenDC)

# ---------------------------------------------------------------------------
# 托盘图标 / 气泡通知
# ---------------------------------------------------------------------------

proc activePlanName(plans: seq[PowerPlan]): string =
  let active = activePlanGuid()
  for plan in plans:
    if plan.guid == active:
      return plan.name
  return ""

proc addTrayIcon(tooltip: string) =
  var nid = NOTIFYICONDATAW(
    cbSize: DWORD sizeof(NOTIFYICONDATAW),
    hWnd: gHwnd,
    uID: IdTrayIcon,
    uFlags: NIF_MESSAGE or NIF_ICON or NIF_TIP,
    uCallbackMessage: WmTrayCallback,
    hIcon: gIcon)
  nid.szTip << T(tooltip)
  Shell_NotifyIconW(NIM_ADD, &nid)

proc modifyTrayIcon(tooltip: string) =
  var nid = NOTIFYICONDATAW(
    cbSize: DWORD sizeof(NOTIFYICONDATAW),
    hWnd: gHwnd,
    uID: IdTrayIcon,
    uFlags: NIF_TIP,
    hIcon: gIcon)
  nid.szTip << T(tooltip)
  Shell_NotifyIconW(NIM_MODIFY, &nid)

proc removeTrayIcon() =
  var nid = NOTIFYICONDATAW(
    cbSize: DWORD sizeof(NOTIFYICONDATAW),
    hWnd: gHwnd,
    uID: IdTrayIcon)
  Shell_NotifyIconW(NIM_DELETE, &nid)

proc showBalloon(title, text: string) =
  var nid = NOTIFYICONDATAW(
    cbSize: DWORD sizeof(NOTIFYICONDATAW),
    hWnd: gHwnd,
    uID: IdTrayIcon,
    uFlags: NIF_INFO,
    dwInfoFlags: NIIF_INFO)
  nid.szInfoTitle << T(title)
  nid.szInfo << T(text)
  Shell_NotifyIconW(NIM_MODIFY, &nid)

var gTrayAdded = false

proc refreshTooltip() =
  let plans = enumPlans()
  let name = activePlanName(plans)
  let tooltip = if name.len > 0: AppTitle & " - " & name else: AppTitle
  if gTrayAdded:
    modifyTrayIcon(tooltip)
  else:
    addTrayIcon(tooltip)
    gTrayAdded = true

# ---------------------------------------------------------------------------
# 右键菜单
# ---------------------------------------------------------------------------

proc showTrayMenu() =
  let plans = enumPlans()
  let active = activePlanGuid()
  let hMenu = CreatePopupMenu()

  for i, plan in plans:
    var flags = UINT MF_STRING or MFT_RADIOCHECK
    if plan.guid == active:
      flags = flags or MF_CHECKED
    AppendMenuW(hMenu, flags, CmdBase + i, T(plan.name))

  AppendMenuW(hMenu, MF_SEPARATOR, 0, nil)
  var autoFlags = UINT MF_STRING
  if isAutoStartEnabled():
    autoFlags = autoFlags or MF_CHECKED
  AppendMenuW(hMenu, autoFlags, CmdAutoStart, T("开机自启动"))
  AppendMenuW(hMenu, MF_SEPARATOR, 0, nil)
  AppendMenuW(hMenu, MF_STRING, CmdExit, T("退出"))

  # 任务栏图标的弹出菜单需要先置为前台窗口
  SetForegroundWindow(gHwnd)
  var pt: POINT
  GetCursorPos(&pt)
  let cmd = TrackPopupMenu(hMenu,
    TPM_RETURNCMD or TPM_RIGHTALIGN or TPM_BOTTOMALIGN,
    pt.x, pt.y, 0, gHwnd, nil)
  discard PostMessageW(gHwnd, WM_NULL, 0, 0)
  DestroyMenu(hMenu)

  if cmd == 0:
    return
  elif cmd == CmdExit:
    DestroyWindow(gHwnd)
  elif cmd == CmdAutoStart:
    setAutoStart(not isAutoStartEnabled())
  elif cmd >= CmdBase and cmd - CmdBase < plans.len:
    let plan = plans[cmd - CmdBase]
    if setActivePlan(&plan.guid):
      refreshTooltip()
      showBalloon(AppTitle, "已切换到：" & plan.name)
    else:
      showBalloon(AppTitle, "切换失败：" & plan.name)

# ---------------------------------------------------------------------------
# 窗口过程与消息循环
# ---------------------------------------------------------------------------

proc wndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  if msg == WmTrayCallback:
    case lParam
    of WM_RBUTTONUP, WM_LBUTTONDBLCLK:
      showTrayMenu()
    else:
      discard
    return 0
  elif gTaskbarCreated != 0 and msg == gTaskbarCreated:
    # 任务栏重启（explorer 崩溃等）后重建托盘图标
    refreshTooltip()
    return 0

  case msg
  of WM_DESTROY:
    removeTrayIcon()
    PostQuitMessage(0)
    return 0
  else:
    return DefWindowProcW(hwnd, msg, wParam, lParam)

proc main() =
  let hInstance = GetModuleHandleW(nil)
  gIcon = makeTrayIcon()
  gTaskbarCreated = RegisterWindowMessageW(T("TaskbarCreated"))

  let className = T("PowerPlanSwitcherWnd")
  var wc = WNDCLASSW(
    style: 0,
    lpfnWndProc: wndProc,
    cbClsExtra: 0,
    cbWndExtra: 0,
    hInstance: hInstance,
    hIcon: 0,
    hCursor: 0,
    hbrBackground: 0,
    lpszMenuName: nil,
    lpszClassName: className)
  RegisterClassW(&wc)

  gHwnd = CreateWindowExW(0, className, T(AppTitle), 0,
    0, 0, 0, 0, 0, 0, hInstance, nil)
  if gHwnd == 0:
    quit("创建窗口失败")

  refreshTooltip()

  var msg: MSG
  while GetMessageW(&msg, 0, 0, 0) > 0:
    TranslateMessage(&msg)
    DispatchMessageW(&msg)

  DeleteObject(gIcon)

main()
