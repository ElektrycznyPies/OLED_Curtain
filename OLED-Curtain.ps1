<# OLED Curtain

Regulated dimming curtain and cursor flashlight for Windows 11.
Start: START-OLED-Curtain.cmd or powershell.exe -NoProfile -STA -File .\OLED-Curtain.ps1
Ctrl+Alt+Space: pause; Ctrl+Alt+M: menu; Ctrl+Alt+Q: end script. Read readme.md.
Made by Dariusz "Zen" Żukowski with GPT 6, 2026. Posted on GitHub at:
https://github.com/ElektrycznyPies/OLED_Curtain
#>

[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'FocusShade\settings.json'),
    [switch]$StartPaused,
    [switch]$ValidateOnly,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'FocusShade wymaga Windows 11.' }
$ConfigPath = [IO.Path]::GetFullPath($ConfigPath)
if ($PSVersionTable.PSEdition -ne 'Desktop' -or [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    if (-not $PSCommandPath) { throw 'Zapisz skrypt do pliku i uruchom przez Windows PowerShell 5.1 -STA.' }
    $fileLiteral = $PSCommandPath.Replace("'", "''")
    $configLiteral = $ConfigPath.Replace("'", "''")
    $invoke = "& '$fileLiteral' -ConfigPath '$configLiteral'"
    if ($StartPaused) { $invoke += ' -StartPaused' }
    if ($ValidateOnly) { $invoke += ' -ValidateOnly' }
    if ($SelfTest) { $invoke += ' -SelfTest' }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($invoke))
    $child = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @('-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded) -Wait -PassThru
    if ($child.ExitCode -ne 0) { throw "FocusShade zakończył się kodem $($child.ExitCode)." }
    return
}
try {
    Add-Type -AssemblyName @('System.Windows.Forms', 'System.Drawing', 'System.Web.Extensions', 'UIAutomationClient', 'UIAutomationTypes', 'WindowsBase')
    if (-not ('FocusShadeV2.Entry' -as [type])) {
        $source = @'
// FocusShade 2.0.4. Windows PowerShell 5.1 / .NET Framework 4.8 / Windows 11.
// All drawing is black with premultiplied per-pixel alpha. No screen capture.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;

namespace FocusShadeV2 {
    public sealed class Profile {
        public int Top = 72, Bottom = 0, Left = 0, Right = 0;
        public bool AlwaysReveal = false;
        public Profile Copy() { return (Profile)MemberwiseClone(); }
        public void Normalize() {
            Top = Math.Max(0, Math.Min(2000, Top)); Bottom = Math.Max(0, Math.Min(2000, Bottom));
            Left = Math.Max(0, Math.Min(2000, Left)); Right = Math.Max(0, Math.Min(2000, Right));
        }
    }
    public sealed class Settings {
        public int Version = 2;
        public double CurtainTransmission = 15, PanelTransmission = 50;
        public double DiameterPercent = 100.0 / 6, SolidCenterPercent = 55;
        public double MouseIdleSeconds = 3, FadeSeconds = 0.7, MaxOcclusionPercent = 10;
        public int FramesPerSecond = 30, WindowScanMs = 200;
        public bool PauseFullscreen = true, FullscreenAllMonitors = false;
        public bool KeyboardFocus = true;
        public bool RevealActiveField = true;
        public double KeyboardFallbackSeconds = 4;
        public bool ShowHamburger = true, MoveHamburger = true;
        public int HamburgerMoveSeconds = 60, HamburgerSize = 28, HamburgerBrightness = 135;
        public bool HamburgerLeft = false;
        public double HamburgerPositionPercent = 65;
        public string PauseHotkey = "Ctrl+Alt+Space", MenuHotkey = "Ctrl+Alt+M", ExitHotkey = "Ctrl+Alt+Q";
        public string RaiseTopHotkey = "Ctrl+Alt+Up", LowerTopHotkey = "Ctrl+Alt+Down";
        public Dictionary<string, Profile> Profiles = new Dictionary<string, Profile>(StringComparer.OrdinalIgnoreCase);
        public Settings() {
            Profiles["*"] = new Profile();
            Profiles["winword"] = new Profile { Top = 164, Bottom = 26 };
            Profiles["foxitpdfreader"] = new Profile { Top = 148, Bottom = 26 };
            Profiles["foxitreader"] = new Profile { Top = 148, Bottom = 26 };
            Profiles["inkscape"] = new Profile { Top = 124, Bottom = 48, Left = 42 };
            Profiles["brave"] = new Profile { Top = 112 };
            Profiles["randominfobar"] = new Profile { Top = 0, AlwaysReveal = true };
        }
        public static double Clamp(double v, double lo, double hi) {
            if (Double.IsNaN(v) || Double.IsInfinity(v)) return lo;
            return Math.Max(lo, Math.Min(hi, v));
        }
        public void Normalize() {
            CurtainTransmission = Clamp(CurtainTransmission, 0, 100);
            PanelTransmission = Clamp(PanelTransmission, 0, 100);
            DiameterPercent = Clamp(DiameterPercent, 2, 100);
            SolidCenterPercent = Clamp(SolidCenterPercent, 0, 95);
            MouseIdleSeconds = Clamp(MouseIdleSeconds, 1, 86400);
            FadeSeconds = Clamp(FadeSeconds, 0, 10);
            MaxOcclusionPercent = Clamp(MaxOcclusionPercent, 0, 99);
            KeyboardFallbackSeconds = Clamp(KeyboardFallbackSeconds, 1, 60);
            FramesPerSecond = Math.Max(10, Math.Min(90, FramesPerSecond));
            WindowScanMs = Math.Max(75, Math.Min(2000, WindowScanMs));
            HamburgerMoveSeconds = Math.Max(15, Math.Min(86400, HamburgerMoveSeconds));
            HamburgerSize = Math.Max(18, Math.Min(64, HamburgerSize));
            HamburgerBrightness = Math.Max(30, Math.Min(255, HamburgerBrightness));
            HamburgerPositionPercent = Clamp(HamburgerPositionPercent, 5, 95);
            Dictionary<string, Profile> clean = new Dictionary<string, Profile>(StringComparer.OrdinalIgnoreCase);
            if (Profiles != null) foreach (KeyValuePair<string, Profile> p in Profiles) {
                if (String.IsNullOrWhiteSpace(p.Key) || p.Value == null) continue;
                p.Value.Normalize(); clean[NormalizeProcess(p.Key)] = p.Value;
            }
            if (!clean.ContainsKey("*")) clean["*"] = new Profile();
            Profiles = clean;
        }
        public static string NormalizeProcess(string value) {
            value = Path.GetFileName(value.Trim()).ToLowerInvariant();
            return value.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? value.Substring(0, value.Length - 4) : value;
        }
        public Profile For(string process) {
            Profile p;
            return Profiles.TryGetValue(process ?? "", out p) ? p : Profiles["*"];
        }
        public Settings Copy() {
            JavaScriptSerializer j = new JavaScriptSerializer();
            Settings s = j.Deserialize<Settings>(j.Serialize(this)); s.Normalize(); return s;
        }
        public static Settings Load(string path, out string warning) {
            warning = null;
            if (!File.Exists(path)) return new Settings();
            try {
                Settings s = new JavaScriptSerializer().Deserialize<Settings>(File.ReadAllText(path, Encoding.UTF8));
                if (s == null) throw new InvalidDataException("Pusty plik ustawień.");
                s.Normalize(); return s;
            } catch (Exception e) {
                // Preserve the user's file. Do not silently replace corrupt data.
                warning = "Nie można odczytać ustawień. Użyto wartości początkowych.\n" + e.Message;
                return new Settings();
            }
        }
        public void Save(string path) {
            Normalize(); string directory = Path.GetDirectoryName(path);
            if (!String.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
            string tmp = path + ".tmp";
            File.WriteAllText(tmp, new JavaScriptSerializer().Serialize(this), new UTF8Encoding(false));
            if (File.Exists(path)) File.Replace(tmp, path, path + ".bak");
            else File.Move(tmp, path);
        }
    }

    internal static class N {
        internal const int GWL_STYLE = -16, GWL_EXSTYLE = -20;
        internal const long WS_CAPTION = 0x00C00000, WS_THICKFRAME = 0x00040000;
        internal const long WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000;
        internal const int WS_EX_LAYERED = 0x80000, WS_EX_TRANSPARENT = 0x20;
        internal const uint SWP_NOSIZE = 1, SWP_NOMOVE = 2, SWP_NOACTIVATE = 0x10;
        internal static readonly IntPtr Topmost = new IntPtr(-1);
        [StructLayout(LayoutKind.Sequential)] internal struct RECT {
            internal int L, T, R, B;
            internal RECT(Rectangle r) { L=r.Left; T=r.Top; R=r.Right; B=r.Bottom; }
            internal Rectangle Rect { get { return Rectangle.FromLTRB(L,T,R,B); } }
        }
        [StructLayout(LayoutKind.Sequential)] internal struct POINT { internal int X,Y; internal POINT(int x,int y) { X=x; Y=y; } }
        [StructLayout(LayoutKind.Sequential)] internal struct SIZE { internal int W,H; internal SIZE(int w,int h) { W=w; H=h; } }
        [StructLayout(LayoutKind.Sequential, Pack=1)] internal struct BLEND { internal byte Op,Flags,Alpha,Format; }
        [StructLayout(LayoutKind.Sequential)] internal struct ULWI {
            internal uint cbSize; internal IntPtr hdcDst, pptDst, psize, hdcSrc, pptSrc;
            internal uint crKey; internal IntPtr pblend; internal uint flags; internal IntPtr dirty;
        }
        [StructLayout(LayoutKind.Sequential)] internal struct BIH {
            internal uint Size; internal int Width,Height; internal ushort Planes,BitCount;
            internal uint Compression,SizeImage; internal int XPels,YPels; internal uint Used,Important;
        }
        [StructLayout(LayoutKind.Sequential)] internal struct BITMAPINFO { internal BIH Header; internal uint Color; }
        [StructLayout(LayoutKind.Sequential)] internal struct KBD { internal uint vk,scan,flags,time; internal UIntPtr extra; }
        [StructLayout(LayoutKind.Sequential)] internal struct GUITHREADINFO {
            internal uint cbSize,flags; internal IntPtr active,focus,capture,menuOwner,moveSize,caret; internal RECT caretRect;
        }
        internal delegate bool EnumProc(IntPtr h, IntPtr data);
        internal delegate void WinEventProc(IntPtr hook,uint ev,IntPtr h,int obj,int child,uint thread,uint time);
        internal delegate IntPtr HookProc(int n,IntPtr wp,IntPtr lp);
        [DllImport("user32.dll")] internal static extern bool EnumWindows(EnumProc callback,IntPtr data);
        [DllImport("user32.dll")] internal static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] internal static extern IntPtr GetAncestor(IntPtr h,uint flags);
        [DllImport("user32.dll")] internal static extern IntPtr GetWindow(IntPtr h,uint cmd);
        [DllImport("user32.dll")] internal static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] internal static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] internal static extern bool GetWindowRect(IntPtr h,out RECT r);
        [DllImport("user32.dll")] internal static extern bool GetClientRect(IntPtr h,out RECT r);
        [DllImport("user32.dll")] internal static extern bool ClientToScreen(IntPtr h,ref POINT p);
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] internal static extern int GetClassName(IntPtr h,StringBuilder b,int max);
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] internal static extern int GetWindowText(IntPtr h,StringBuilder b,int max);
        [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
        [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetLong64(IntPtr h,int index);
        [DllImport("user32.dll",EntryPoint="GetWindowLongW")] static extern int GetLong32(IntPtr h,int index);
        internal static long Style(IntPtr h,int index) { return IntPtr.Size==8 ? GetLong64(h,index).ToInt64() : GetLong32(h,index); }
        [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(IntPtr h);
        [DllImport("user32.dll")] internal static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("dwmapi.dll")] internal static extern int DwmGetWindowAttribute(IntPtr h,int attr,out RECT r,int size);
        [DllImport("dwmapi.dll",EntryPoint="DwmGetWindowAttribute")] internal static extern int DwmInt(IntPtr h,int attr,out int result,int size);
        [DllImport("user32.dll")] internal static extern bool GetCursorPos(out POINT p);
        [DllImport("user32.dll")] internal static extern short GetAsyncKeyState(int v);
        [DllImport("user32.dll")] internal static extern bool GetGUIThreadInfo(uint id,ref GUITHREADINFO info);
        [DllImport("user32.dll",SetLastError=true)] internal static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int cx,int cy,uint flags);
        [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] internal static extern bool SetProp(IntPtr h,string name,IntPtr value);
        [DllImport("user32.dll",CharSet=CharSet.Unicode)] internal static extern IntPtr RemoveProp(IntPtr h,string name);
        [DllImport("user32.dll",SetLastError=true)] internal static extern bool RegisterHotKey(IntPtr h,int id,uint mods,uint key);
        [DllImport("user32.dll")] internal static extern bool UnregisterHotKey(IntPtr h,int id);
        [DllImport("user32.dll")] internal static extern IntPtr SetWinEventHook(uint first,uint last,IntPtr module,WinEventProc callback,uint pid,uint thread,uint flags);
        [DllImport("user32.dll")] internal static extern bool UnhookWinEvent(IntPtr hook);
        [DllImport("user32.dll",SetLastError=true)] internal static extern IntPtr SetWindowsHookEx(int kind,HookProc callback,IntPtr module,uint thread);
        [DllImport("user32.dll")] internal static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] internal static extern IntPtr CallNextHookEx(IntPtr hook,int n,IntPtr wp,IntPtr lp);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] internal static extern IntPtr GetModuleHandle(string module);
        [DllImport("kernel32.dll")] internal static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
        [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] internal static extern bool QueryFullProcessImageName(IntPtr h,uint flags,StringBuilder name,ref int size);
        [DllImport("kernel32.dll")] internal static extern bool CloseHandle(IntPtr h);
        [DllImport("shell32.dll")] internal static extern int SHQueryUserNotificationState(out int state);
        [DllImport("user32.dll")] internal static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] internal static extern int ReleaseDC(IntPtr h,IntPtr dc);
        [DllImport("gdi32.dll")] internal static extern IntPtr CreateCompatibleDC(IntPtr dc);
        [DllImport("gdi32.dll")] internal static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll")] internal static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
        [DllImport("gdi32.dll")] internal static extern bool DeleteObject(IntPtr obj);
        [DllImport("gdi32.dll")] internal static extern IntPtr CreateDIBSection(IntPtr dc,ref BITMAPINFO info,uint usage,out IntPtr bits,IntPtr section,uint offset);
        [DllImport("user32.dll",SetLastError=true)] internal static extern bool UpdateLayeredWindowIndirect(IntPtr h,ref ULWI info);
        [DllImport("user32.dll",SetLastError=true)] internal static extern bool UpdateLayeredWindow(IntPtr h,IntPtr dst,ref POINT p,ref SIZE s,IntPtr src,ref POINT srcP,uint key,ref BLEND blend,uint flags);
        internal static string Class(IntPtr h) { StringBuilder b=new StringBuilder(256); GetClassName(h,b,b.Capacity); return b.ToString(); }
        internal static Rectangle Bounds(IntPtr h) {
            RECT r;
            if (DwmGetWindowAttribute(h,9,out r,Marshal.SizeOf(typeof(RECT)))==0 && r.R>r.L && r.B>r.T) return r.Rect;
            return GetWindowRect(h,out r) ? r.Rect : Rectangle.Empty;
        }
        internal static Rectangle ClientBounds(IntPtr h) {
            RECT r; POINT p=new POINT();
            if (!GetClientRect(h,out r) || !ClientToScreen(h,ref p)) return Rectangle.Empty;
            return new Rectangle(p.X,p.Y,Math.Max(0,r.R),Math.Max(0,r.B));
        }
        internal static bool Down(int key) { return (GetAsyncKeyState(key)&0x8000)!=0; }
        internal static bool Desktop(string cls) { return cls=="Progman" || cls=="WorkerW" || cls=="SHELLDLL_DefView"; }
        internal static bool Taskbar(string cls) { return cls=="Shell_TrayWnd" || cls=="Shell_SecondaryTrayWnd"; }
        internal static bool ShellUI(string cls,string proc) {
            return cls=="MultitaskingViewFrame" || cls=="TaskSwitcherWnd" || cls=="XamlExplorerHostIslandWindow" ||
                proc=="startmenuexperiencehost" || proc=="searchhost" || proc=="searchapp" ||
                proc=="lockapp" || proc=="shellexperiencehost";
        }
    }

    internal static class Geo {
        internal static long Area(Rectangle r) { return r.Width<=0||r.Height<=0 ? 0 : (long)r.Width*r.Height; }
        internal static List<Rectangle> Subtract(List<Rectangle> pieces,Rectangle cover) {
            List<Rectangle> next=new List<Rectangle>();
            foreach(Rectangle r in pieces) {
                Rectangle q=Rectangle.Intersect(r,cover);
                if(Area(q)==0) { next.Add(r); continue; }
                if(q.Top>r.Top) next.Add(Rectangle.FromLTRB(r.Left,r.Top,r.Right,q.Top));
                if(q.Bottom<r.Bottom) next.Add(Rectangle.FromLTRB(r.Left,q.Bottom,r.Right,r.Bottom));
                if(q.Left>r.Left) next.Add(Rectangle.FromLTRB(r.Left,q.Top,q.Left,q.Bottom));
                if(q.Right<r.Right) next.Add(Rectangle.FromLTRB(q.Right,q.Top,r.Right,q.Bottom));
            }
            return next;
        }
        internal static List<Rectangle> OnScreens(Rectangle r,IEnumerable<Rectangle> screens) {
            // Deduplicate mirrored/overlapping monitor rectangles.
            List<Rectangle> result=new List<Rectangle>();
            foreach(Rectangle screen in screens) {
                Rectangle q=Rectangle.Intersect(r,screen);
                if(Area(q)==0) continue;
                List<Rectangle> fresh=new List<Rectangle>{q};
                foreach(Rectangle existing in result) fresh=Subtract(fresh,existing);
                result.AddRange(fresh);
            }
            return result;
        }
        internal static double VisibleFraction(Rectangle r,IEnumerable<Rectangle> screens,IEnumerable<Rectangle> above) {
            List<Rectangle> pieces=OnScreens(r,screens);
            long total=pieces.Sum(x=>Area(x));
            if(total==0) return 0;
            foreach(Rectangle cover in above) { pieces=Subtract(pieces,cover); if(pieces.Count==0) return 0; }
            return (double)pieces.Sum(x=>Area(x))/total;
        }
        internal static Rectangle Work(Rectangle outer,Profile p,double dpi) {
            int l=(int)Math.Round(p.Left*dpi),t=(int)Math.Round(p.Top*dpi);
            int r=(int)Math.Round(p.Right*dpi),b=(int)Math.Round(p.Bottom*dpi);
            if(l+r>=outer.Width || t+b>=outer.Height) return Rectangle.Empty;
            return Rectangle.FromLTRB(outer.Left+l,outer.Top+t,outer.Right-r,outer.Bottom-b);
        }
        internal static bool Near(Rectangle a,Rectangle b,int tolerance) {
            return Area(a)>0 && Math.Abs(a.Left-b.Left)<=tolerance && Math.Abs(a.Top-b.Top)<=tolerance &&
                Math.Abs(a.Right-b.Right)<=tolerance && Math.Abs(a.Bottom-b.Bottom)<=tolerance;
        }
    }
    internal sealed class Win {
        internal IntPtr Handle,Owner;
        internal Rectangle Outer,Work;
        internal string Process,Class;
        internal long Style,ExStyle;
        internal double Dpi;
        internal bool Reveal,Auxiliary,Own;
    }
    internal sealed class TaskbarYield {
        readonly Dictionary<string,double> until=new Dictionary<string,double>();
        internal static Rectangle VisiblePart(Rectangle taskbar,Rectangle screen) {
            Rectangle r=Rectangle.Intersect(taskbar,screen);
            // Auto-hide leaves a thin activation strip, not an open taskbar.
            return r.Width>6 && r.Height>6 ? r : Rectangle.Empty;
        }
        internal static bool Requested(Rectangle screen,Point mouse,IEnumerable<Rectangle> taskbars) {
            if(!screen.Contains(mouse)) return false;
            // Windows 11's bottom edge must be reachable even before Explorer starts animating.
            if(mouse.Y>=screen.Bottom-8) return true;
            return taskbars.Any(r=>VisiblePart(r,screen).Contains(mouse));
        }
        internal bool Active(string monitor,bool requested,double now) {
            if(requested) until[monitor]=now+0.6;
            double deadline; return until.TryGetValue(monitor,out deadline) && now<deadline;
        }
        internal void Reset() { until.Clear(); }
    }
    internal sealed class Layout {
        internal List<Win> Windows=new List<Win>(); // top to bottom
        internal List<Rectangle> Taskbars=new List<Rectangle>();
        internal HashSet<string> Fullscreen=new HashSet<string>();
        internal bool Shell,Desktop,NativeMenu;
        internal string Signature="";
    }
    internal sealed class WindowReader {
        readonly int pid=Process.GetCurrentProcess().Id;
        readonly Dictionary<uint,string> names=new Dictionary<uint,string>();
        readonly HashSet<IntPtr> ownSurfaces;
        internal WindowReader(HashSet<IntPtr> surfaces) { ownSurfaces=surfaces; }
        internal string ProcessName(IntPtr h) {
            uint p; N.GetWindowThreadProcessId(h,out p);
            if(p==0) return "";
            string result;
            if(names.TryGetValue(p,out result)) return result;
            IntPtr ph=N.OpenProcess(0x1000,false,p);
            try {
                if(ph==IntPtr.Zero) return "";
                StringBuilder b=new StringBuilder(32768); int size=b.Capacity;
                if(!N.QueryFullProcessImageName(ph,0,b,ref size)) return "";
                result=Settings.NormalizeProcess(b.ToString());
                if(names.Count>512) names.Clear(); names[p]=result; return result;
            } finally { if(ph!=IntPtr.Zero) N.CloseHandle(ph); }
        }
        internal Layout Read(Settings settings,Screen[] screens,IntPtr foreground,IntPtr previousApp) {
            names.Clear(); // Process IDs can be reused after an application exits.
            Layout layout=new Layout();
            uint fgPid; uint fgThread=N.GetWindowThreadProcessId(foreground,out fgPid);
            string fgClass=N.Class(foreground), fgProcess=ProcessName(foreground);
            layout.Desktop=N.Desktop(fgClass);
            layout.Shell=N.ShellUI(fgClass,fgProcess) || N.Taskbar(fgClass);
            N.GUITHREADINFO gui=new N.GUITHREADINFO(); gui.cbSize=(uint)Marshal.SizeOf(typeof(N.GUITHREADINFO));
            if(fgThread!=0 && N.GetGUIThreadInfo(fgThread,ref gui)) layout.NativeMenu=(gui.flags&0x1C)!=0;
            IntPtr relevant=fgPid==pid ? previousApp : foreground;
            IntPtr activeRoot=N.GetAncestor(relevant,3); // GA_ROOTOWNER includes a modal dialog's owner.
            List<Rectangle> screenRects=screens.Select(x=>x.Bounds).ToList();
            N.EnumProc callback=delegate(IntPtr h,IntPtr unused) {
                if(ownSurfaces.Contains(h) || !N.IsWindowVisible(h) || N.IsIconic(h)) return true;
                int cloaked; if(N.DwmInt(h,14,out cloaked,4)==0 && cloaked!=0) return true;
                string cls=N.Class(h);
                if(N.Desktop(cls)) return true;
                if(N.Taskbar(cls)) {
                    N.RECT raw;
                    if(N.GetWindowRect(h,out raw)) foreach(Rectangle screen in screenRects) {
                        Rectangle taskbarPart=TaskbarYield.VisiblePart(raw.Rect,screen);
                        if(!taskbarPart.IsEmpty) layout.Taskbars.Add(taskbarPart);
                    }
                    return true;
                }
                Rectangle bounds=N.Bounds(h);
                if(bounds.Width<3 || bounds.Height<3 || !screenRects.Any(x=>x.IntersectsWith(bounds))) return true;
                uint p; N.GetWindowThreadProcessId(h,out p);
                long ex=N.Style(h,N.GWL_EXSTYLE);
                string process=ProcessName(h);
                // Ignore invisible helper/shadow windows; transient menus are handled below.
                if(cls=="SysShadow" || cls=="IME" || cls=="MSCTFIME UI" || cls=="CiceroUIWndFrame") return true;
                if(cls=="XamlExplorerHostIslandWindow" && (bounds.Width<150 || bounds.Height<100)) return true;
                Win w=new Win {Handle=h,Owner=N.GetWindow(h,4),Outer=bounds,Class=cls,Process=process,
                    ExStyle=ex,Style=N.Style(h,N.GWL_STYLE),Own=p==pid};
                uint dpi=N.GetDpiForWindow(h); w.Dpi=dpi==0?1:dpi/96.0;
                w.Auxiliary=w.Own || w.Owner!=IntPtr.Zero || cls=="#32770" || cls=="#32768" || cls=="tooltips_class32";
                Profile profile=settings.For(process);
                w.Work=w.Auxiliary ? bounds : Geo.Work(bounds,profile,w.Dpi);
                bool eligible=(ex&N.WS_EX_NOACTIVATE)==0 && (ex&N.WS_EX_TOOLWINDOW)==0 && bounds.Width>=120*w.Dpi && bounds.Height>=80*w.Dpi;
                double visible=Geo.VisibleFraction(Geo.Area(w.Work)>0?w.Work:w.Outer,screenRects,
                    layout.Windows.Where(x=>!x.Own).Select(x=>x.Outer));
                w.Reveal=w.Own || profile.AlwaysReveal || h==relevant || h==activeRoot ||
                    (w.Auxiliary && (cls=="#32768" || cls=="tooltips_class32" || w.Owner==relevant || w.Owner==activeRoot)) ||
                    (eligible && visible+0.000001>=1-settings.MaxOcclusionPercent/100);
                layout.Windows.Add(w);
                if(settings.PauseFullscreen && eligible && !w.Own && visible>=0.90 &&
                    (w.Style&(N.WS_CAPTION|N.WS_THICKFRAME))==0) {
                    Rectangle client=N.ClientBounds(h);
                    foreach(Screen s in screens) if(Geo.Near(bounds,s.Bounds,3) && Geo.Near(client,s.Bounds,3)) layout.Fullscreen.Add(s.DeviceName);
                }
                return true;
            };
            N.EnumWindows(callback,IntPtr.Zero);
            if(settings.PauseFullscreen) {
                int state;
                if(N.SHQueryUserNotificationState(out state)==0 && state==3 && layout.Fullscreen.Count==0)
                    foreach(Screen s in screens) layout.Fullscreen.Add(s.DeviceName);
                if(settings.FullscreenAllMonitors && layout.Fullscreen.Count>0)
                    foreach(Screen s in screens) layout.Fullscreen.Add(s.DeviceName);
            }
            StringBuilder signature=new StringBuilder();
            foreach(Win w in layout.Windows) signature.Append(w.Handle).Append(':').Append(w.Outer).Append(':').Append(w.Work).Append(':').Append(w.Reveal).Append(':').Append(w.Auxiliary).Append(';');
            foreach(Rectangle r in layout.Taskbars) signature.Append("taskbar:").Append(r).Append(';');
            layout.Signature=signature.ToString(); return layout;
        }
    }

    internal sealed class Spot {
        internal Point Center;
        internal int Radius,Strength;
        internal Rectangle FocusRect;
        internal List<Rectangle> ActiveFields=new List<Rectangle>();
        internal Rectangle Bounds { get { return Strength<=0 ? Rectangle.Empty : new Rectangle(Center.X-Radius,Center.Y-Radius,Radius*2+1,Radius*2+1); } }
        internal Rectangle DrawBounds(Rectangle screen) {
            Rectangle r=Rectangle.Intersect(Bounds,screen);
            foreach(Rectangle part in new[]{FocusRect}.Concat(ActiveFields)) {
                Rectangle q=Rectangle.Intersect(part,screen);
                if(Geo.Area(q)>0)r=Geo.Area(r)>0?Rectangle.Union(r,q):q;
            }
            return r;
        }
        internal static int FadeStrength(double age,double idleSeconds,double fadeSeconds) {
            double strength=age<=idleSeconds ? 1 : fadeSeconds<=0?0:1-(age-idleSeconds)/fadeSeconds;
            return (int)Math.Round(255*Math.Max(0,Math.Min(1,strength)));
        }
    }
    internal abstract class OverlayForm : Form {
        protected override void OnHandleCreated(EventArgs e) {
            // A screen-sized dimmer must not make Explorer demote the taskbar.
            // Set BEFORE first Show(), and again if WinForms recreates the HWND.
            // MarkFullscreenWindow(false) alone would still allow heuristic detection.
            if(!N.SetProp(Handle,"NonRudeHWND",new IntPtr(1)))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),
                    "Nie można oznaczyć nakładki jako niepełnoekranowej.");
            base.OnHandleCreated(e);
        }
        protected override void WndProc(ref Message m) {
            // Remove our property while this exact HWND still exists. Do not access
            // Form.Handle from OnHandleDestroyed: that could recreate the handle.
            if(m.Msg==0x82) N.RemoveProp(m.HWnd,"NonRudeHWND"); // WM_NCDESTROY
            base.WndProc(ref m);
        }
    }
    internal sealed class Curtain : OverlayForm {
        internal readonly Screen Display;
        readonly Rectangle screen;
        byte[] baseAlpha,kernel;
        int[] frame;
        int kernelRadius=-1, kernelSolid=-1;
        bool fullDirty=true, indirectWorks=true;
        Rectangle previousDirty;
        string previousSpot="";
        IntPtr dc,bitmap,oldBitmap,bits;
        IntPtr dstPtr,sizePtr,srcPtr,blendPtr,dirtyPtr;
        internal Curtain(Screen display) {
            Display=display; screen=display.Bounds;
            FormBorderStyle=FormBorderStyle.None; ShowInTaskbar=false; StartPosition=FormStartPosition.Manual;
            AutoScaleMode=AutoScaleMode.None; Bounds=screen; TopMost=true;
            int count=checked(screen.Width*screen.Height);
            baseAlpha=new byte[count]; frame=new int[count];
            dc=N.CreateCompatibleDC(IntPtr.Zero);
            N.BITMAPINFO info=new N.BITMAPINFO();
            info.Header.Size=(uint)Marshal.SizeOf(typeof(N.BIH)); info.Header.Width=screen.Width;
            info.Header.Height=-screen.Height; info.Header.Planes=1; info.Header.BitCount=32;
            bitmap=N.CreateDIBSection(dc,ref info,0,out bits,IntPtr.Zero,0);
            if(dc==IntPtr.Zero || bitmap==IntPtr.Zero || bits==IntPtr.Zero) { Dispose(); throw new InvalidOperationException("Nie można utworzyć powierzchni kurtyny."); }
            oldBitmap=N.SelectObject(dc,bitmap);
            dstPtr=Pack(new N.POINT(screen.X,screen.Y)); sizePtr=Pack(new N.SIZE(screen.Width,screen.Height));
            srcPtr=Pack(new N.POINT(0,0)); blendPtr=Pack(new N.BLEND {Alpha=255,Format=1}); dirtyPtr=Pack(new N.RECT());
        }
        static IntPtr Pack(object value) { IntPtr p=Marshal.AllocHGlobal(Marshal.SizeOf(value)); Marshal.StructureToPtr(value,p,false); return p; }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams { get { CreateParams p=base.CreateParams; p.ExStyle|=N.WS_EX_LAYERED|N.WS_EX_TRANSPARENT|0x08000080; return p; } }
        protected override void WndProc(ref Message m) {
            if(m.Msg==0x21) { m.Result=new IntPtr(3); return; } // MA_NOACTIVATE
            if(m.Msg==0x84) { m.Result=new IntPtr(-1); return; } // HTTRANSPARENT, also layered WS_EX_TRANSPARENT
            base.WndProc(ref m);
        }
        internal void Rebuild(Layout layout,Settings s) {
            byte curtain=(byte)Math.Round(255*(1-s.CurtainTransmission/100));
            byte panel=(byte)Math.Round(255*(1-s.PanelTransmission/100));
            for(int i=0;i<baseAlpha.Length;i++) baseAlpha[i]=curtain;
            for(int i=layout.Windows.Count-1;i>=0;i--) {
                Win w=layout.Windows[i];
                Fill(w.Outer,w.Reveal ? (w.Auxiliary||s.For(w.Process).AlwaysReveal ? (byte)0 : panel) : curtain);
                if(w.Reveal) Fill(w.Work,0);
            }
            // Explorer surfaces stay clear even when the pointer is elsewhere.
            foreach(Rectangle r in layout.Taskbars) Fill(r,0);
            // Preserve the title-based RIB exception, including its PowerShell version.
            foreach(Win w in layout.Windows) {
                StringBuilder title=new StringBuilder(256);
                N.GetWindowText(w.Handle,title,title.Capacity);
                if(title.ToString()=="Random Info Bar")Fill(w.Outer,0);
            }
            fullDirty=true;
        }
        void Fill(Rectangle global,byte alpha) {
            Rectangle r=Rectangle.Intersect(global,screen); if(Geo.Area(r)==0) return;
            r.Offset(-screen.X,-screen.Y);
            for(int y=r.Top;y<r.Bottom;y++) {
                int start=y*screen.Width+r.Left,end=start+r.Width;
                for(int i=start;i<end;i++) baseAlpha[i]=alpha;
            }
        }
        internal byte AlphaAt(Point global) {
            if(!screen.Contains(global)) return 0;
            return baseAlpha[(global.Y-screen.Y)*screen.Width+global.X-screen.X];
        }
        void Kernel(int radius,int solid) {
            if(kernelRadius==radius && kernelSolid==solid) return;
            int width=radius*2+1; kernel=new byte[checked(width*width)];
            double inner=radius*solid/100.0,fade=Math.Max(1,radius-inner);
            for(int y=0;y<width;y++) for(int x=0;x<width;x++) {
                double d=Math.Sqrt((double)(x-radius)*(x-radius)+(double)(y-radius)*(y-radius));
                double t=Math.Max(0,Math.Min(1,(d-inner)/fade));
                t=t*t*(3-2*t); kernel[y*width+x]=(byte)Math.Round(255*t);
            }
            kernelRadius=radius; kernelSolid=solid;
        }
        internal void Render(Spot spot,Settings settings) {
            string state=spot.Center+":"+spot.Radius+":"+spot.Strength+":"+spot.FocusRect+":"+settings.SolidCenterPercent+
                ":"+String.Join(";",spot.ActiveFields.Select(r=>r.ToString()));
            if(!fullDirty && state==previousSpot && Visible) return;
            Rectangle current=spot.DrawBounds(screen);
            Rectangle focus=Rectangle.Intersect(spot.FocusRect,screen);
            Rectangle dirty=fullDirty?screen:(Geo.Area(previousDirty)>0 && Geo.Area(current)>0?Rectangle.Union(previousDirty,current):Geo.Area(current)>0?current:previousDirty);
            dirty=Rectangle.Intersect(dirty,screen);
            previousSpot=state; previousDirty=current;
            if(Geo.Area(dirty)==0) return;
            Rectangle local=dirty; local.Offset(-screen.X,-screen.Y);
            for(int y=local.Top;y<local.Bottom;y++) {
                int index=y*screen.Width+local.Left,end=index+local.Width;
                for(int i=index;i<end;i++) frame[i]=baseAlpha[i]<<24;
            }
            if(spot.Strength>0 && Geo.Area(Rectangle.Intersect(spot.Bounds,screen))>0) {
                Kernel(spot.Radius,(int)Math.Round(settings.SolidCenterPercent));
                Rectangle circle=Rectangle.Intersect(spot.Bounds,screen);
                int stride=spot.Radius*2+1;
                for(int y=circle.Top;y<circle.Bottom;y++) for(int x=circle.Left;x<circle.Right;x++) {
                    int index=(y-screen.Y)*screen.Width+x-screen.X;
                    int a=baseAlpha[index]; if(a==0) continue;
                    int k=kernel[(y-spot.Center.Y+spot.Radius)*stride+x-spot.Center.X+spot.Radius];
                    int factor=255-((255-k)*spot.Strength+127)/255;
                    frame[index]=((a*factor+127)/255)<<24;
                }
            }
            if(Geo.Area(focus)>0 && spot.Strength>0) {
                // A wide keyboard-focused input (e.g. an address bar) must be readable in full.
                for(int y=focus.Top;y<focus.Bottom;y++) for(int x=focus.Left;x<focus.Right;x++) {
                    int index=(y-screen.Y)*screen.Width+x-screen.X;
                    frame[index]=((baseAlpha[index]*(255-spot.Strength)+127)/255)<<24;
                }
            }
            // The active editor is independent of spotlight strength and mouse inactivity.
            ActiveFieldGeometry.Clear(frame,screen,spot.ActiveFields);
            for(int y=local.Top;y<local.Bottom;y++) {
                int offset=y*screen.Width+local.Left;
                Marshal.Copy(frame,offset,IntPtr.Add(bits,offset*4),local.Width);
            }
            bool wasFull=fullDirty; fullDirty=false;
            if(!Visible) { Show(); wasFull=true; }
            Marshal.StructureToPtr(new N.RECT(local),dirtyPtr,false);
            N.ULWI ul=new N.ULWI { cbSize=(uint)Marshal.SizeOf(typeof(N.ULWI)),pptDst=dstPtr,psize=sizePtr,
                hdcSrc=dc,pptSrc=srcPtr,pblend=blendPtr,flags=2,dirty=wasFull?IntPtr.Zero:dirtyPtr };
            if(indirectWorks && N.UpdateLayeredWindowIndirect(Handle,ref ul)) return;
            indirectWorks=false;
            N.POINT dst=new N.POINT(screen.X,screen.Y),src=new N.POINT(); N.SIZE size=new N.SIZE(screen.Width,screen.Height);
            N.BLEND blend=new N.BLEND {Alpha=255,Format=1};
            if(!N.UpdateLayeredWindow(Handle,IntPtr.Zero,ref dst,ref size,dc,ref src,0,ref blend,2))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(),"Nie można narysować kurtyny.");
        }
        internal void Suspend() { if(Visible) Hide(); fullDirty=true; }
        protected override void Dispose(bool disposing) {
            if(oldBitmap!=IntPtr.Zero && dc!=IntPtr.Zero) N.SelectObject(dc,oldBitmap);
            if(bitmap!=IntPtr.Zero) {N.DeleteObject(bitmap);bitmap=IntPtr.Zero;}
            if(dc!=IntPtr.Zero) {N.DeleteDC(dc);dc=IntPtr.Zero;}
            foreach(IntPtr p in new[]{dstPtr,sizePtr,srcPtr,blendPtr,dirtyPtr}) if(p!=IntPtr.Zero) Marshal.FreeHGlobal(p);
            dstPtr=sizePtr=srcPtr=blendPtr=dirtyPtr=IntPtr.Zero;
            base.Dispose(disposing);
        }
    }

    internal sealed class FocusResult {
        internal Rectangle Bounds; internal IntPtr Foreground; internal int Request;
        internal bool Usable,WideInput,TextEntry;
        internal bool Confirmed,Editable;
    }
    internal static class ActiveFieldGeometry {
        internal static List<Rectangle> Visible(Rectangle field,IntPtr foreground,List<Win> windows) {
            int owner=windows.FindIndex(w=>w.Handle==foreground);
            if(owner<0 || Geo.Area(field)==0)return new List<Rectangle>();
            Rectangle r=Rectangle.Intersect(field,windows[owner].Outer);
            if(Geo.Area(r)==0)return new List<Rectangle>();
            List<Rectangle> pieces=new List<Rectangle>{r};
            for(int i=0;i<owner && pieces.Count>0;i++)pieces=Geo.Subtract(pieces,windows[i].Outer);
            return pieces;
        }
        internal static void Clear(int[] frame,Rectangle screen,IEnumerable<Rectangle> fields) {
            foreach(Rectangle field in fields) {
                Rectangle r=Rectangle.Intersect(field,screen);
                if(Geo.Area(r)==0)continue;
                for(int y=r.Top;y<r.Bottom;y++)Array.Clear(frame,(y-screen.Top)*screen.Width+r.Left-screen.Left,r.Width);
            }
        }
    }
    // Separate from keyboard navigation: pointer motion cannot erase an active editor.
    internal sealed class ActiveFieldState {
        internal IntPtr Foreground;
        internal int Expected;
        internal double RequestedAt;
        Rectangle current;
        double confirmedAt=-100000;
        internal bool Pending {get{return Expected!=0;}}
        internal void Reset(IntPtr foreground) {Foreground=foreground;Invalidate(true);}
        internal void Invalidate(bool clear) {Expected=0;if(clear){current=Rectangle.Empty;confirmedAt=-100000;}}
        internal void Begin(int id,double now) {Expected=id;RequestedAt=now;}
        internal void Observe(FocusResult result,double now) {
            if(Expected==0 || result.Request!=Expected || result.Foreground!=Foreground)return;
            Expected=0;
            // Provider failures briefly retain a known rectangle; a confirmed non-editor clears it.
            if(!result.Confirmed)return;
            current=result.Editable && result.Usable ? result.Bounds : Rectangle.Empty;
            confirmedAt=now;
        }
        internal Rectangle Bounds(double now) {return now-confirmedAt<=2.0 ? current : Rectangle.Empty;}
    }
    internal sealed class ActiveFieldWatcher : IDisposable {
        readonly FocusWorker worker=new FocusWorker(true);
        readonly ActiveFieldState state=new ActiveFieldState();
        int sequence;
        bool pointerWasDown;
        double nextRead;
        internal void FocusMayChange(double now,bool clear) {
            state.Invalidate(clear);nextRead=Math.Min(nextRead,now+0.035);
        }
        internal Rectangle Bounds(double now) {return state.Bounds(now);}
        internal void Tick(double now,IntPtr foreground,Point pointer,bool pointerDown,bool enabled) {
            if(!enabled || foreground==IntPtr.Zero) {
                state.Reset(IntPtr.Zero);nextRead=now;pointerWasDown=pointerDown;return;
            }
            if(state.Foreground!=foreground) {state.Reset(foreground);nextRead=now+0.035;}
            if(pointerDown && !pointerWasDown)FocusMayChange(now,!state.Bounds(now).Contains(pointer));
            pointerWasDown=pointerDown;
            state.Observe(worker.Result,now);
            if(now>=nextRead && (!state.Pending || now-state.RequestedAt>=2.0)) {
                state.Begin(++sequence,now);worker.Request(sequence,foreground);nextRead=now+0.5;
            }
        }
        public void Dispose() {worker.Dispose();}
    }
    // Kept independent of Windows calls so the asynchronous transitions can be regression-tested.
    internal sealed class FocusState {
        internal FocusResult Current;
        internal IntPtr Foreground;
        internal int Requested;
        int completed;
        bool invalidateOnFailure,allowFallback;
        double missingSince=-1,navigationAt=-100000,fallbackUntil=-100000;
        internal bool Pending {get{return Requested!=completed;}}
        internal bool Editing {get{return Current!=null && Current.TextEntry;}}
        internal void Reset(IntPtr foreground) {
            Foreground=foreground;Current=null;Requested=completed=0;
            missingSince=-1;navigationAt=fallbackUntil=-100000;allowFallback=false;
        }
        internal void Navigate(double now,double fallbackSeconds) {
            navigationAt=now;allowFallback=true;
            if(fallbackUntil>now)fallbackUntil=now+fallbackSeconds;
        }
        internal void Typing() {allowFallback=false;}
        internal void Begin(int id,double now,bool actualFocusChange) {
            // A new query does not erase the last usable location.
            Requested=id;invalidateOnFailure=actualFocusChange;
            if(Current==null && missingSince<0)missingSince=now;
        }
        internal void Observe(FocusResult result,double now) {
            if(!Pending || result.Request!=Requested || result.Foreground!=Foreground)return;
            completed=Requested;
            if(result.Usable) {Current=result;missingSince=-1;}
            else if(invalidateOnFailure) {Current=null;if(missingSince<0)missingSince=now;}
        }
        internal bool Fallback(double now,double seconds,bool knownLocation) {
            // Once a genuine navigation failure reveals the desktop, hold it steadily.
            if(fallbackUntil>now)return true;
            if(knownLocation || !allowFallback || now>=navigationAt+seconds)return false;
            if(missingSince<0)missingSince=now;
            if(now-missingSince<0.35)return false;
            fallbackUntil=navigationAt+seconds;return true;
        }
    }
    internal static class KeyboardPolicy {
        internal static bool Modifier(int key) {
            return key==16 || key==17 || key==18 || key==91 || key==92 || (key>=160 && key<=165);
        }
        internal static bool Navigate(int key,bool control,bool alt,bool win,bool altGr,bool desktop,bool editing) {
            if(Modifier(key) || win || (alt && !altGr && (key==9 || key==27)))return false;
            if(desktop)return true; // Includes searching desktop icons by typing their names.
            if(key==9 || key==93)return true;
            if(altGr)return false;
            if(alt || key==121)return true;
            if(control && (key==76 || key==70 || key==72 || key==75 || key==69 || key==79))return true;
            return !editing && (key==13 || (key>=33 && key<=40));
        }
    }
    internal sealed class FocusWorker : IDisposable {
        readonly AutoResetEvent wake=new AutoResetEvent(false);
        readonly object gate=new object();
        readonly Thread thread;
        readonly bool readEditable;
        bool stopping; int sequence; IntPtr foreground;
        FocusResult latest=new FocusResult();
        internal FocusWorker(bool readEditable=false) {
            this.readEditable=readEditable;
            thread=new Thread(Loop); thread.IsBackground=true; thread.Name="FocusShade UI Automation";
            thread.SetApartmentState(ApartmentState.MTA); thread.Start();
        }
        internal void Request(int id,IntPtr fg) { lock(gate) {sequence=id;foreground=fg;} wake.Set(); }
        internal FocusResult Result { get { lock(gate) return latest; } }
        static bool IsEditable(AutomationElement e) {
            ControlType type=e.Current.ControlType;
            object pattern;
            bool text=e.TryGetCurrentPattern(TextPattern.Pattern,out pattern);
            if(type!=ControlType.Edit && type!=ControlType.ComboBox && type!=ControlType.Document && !text)return false;
            object value;
            if(e.TryGetCurrentPattern(ValuePattern.Pattern,out value))return !((ValuePattern)value).Current.IsReadOnly;
            return text && Object.Equals(((TextPattern)pattern).DocumentRange.GetAttributeValue(TextPattern.IsReadOnlyAttribute),false);
        }
        void Loop() {
            N.SetThreadDpiAwarenessContext(new IntPtr(-4));
            while(true) {
                wake.WaitOne(); int id; IntPtr fg;
                lock(gate) {if(stopping) return;id=sequence;fg=foreground;}
                FocusResult result=new FocusResult {Request=id,Foreground=fg};
                try {
                    bool sameForeground=!readEditable || N.GetForegroundWindow()==fg;
                    AutomationElement e=sameForeground?AutomationElement.FocusedElement:null;
                    if(e!=null) {
                        object selection;
                        if(e.Current.ControlType==ControlType.List && e.TryGetCurrentPattern(SelectionPattern.Pattern,out selection)) {
                            AutomationElement[] selected=((SelectionPattern)selection).Current.GetSelection();
                            if(selected.Length>0) e=selected.FirstOrDefault(x=>x.Current.HasKeyboardFocus)??selected[0];
                        }
                        System.Windows.Rect b=e.Current.BoundingRectangle;
                        if(!b.IsEmpty && !Double.IsInfinity(b.X) && !Double.IsInfinity(b.Y) && b.Width>=1 && b.Height>=1) {
                            result.Bounds=new Rectangle((int)Math.Floor(b.X),(int)Math.Floor(b.Y),(int)Math.Ceiling(b.Width),(int)Math.Ceiling(b.Height));
                            result.Usable=!e.Current.IsOffscreen;
                            ControlType type=e.Current.ControlType;
                            result.WideInput=type==ControlType.Edit || type==ControlType.ComboBox;
                            result.TextEntry=result.WideInput || type==ControlType.Document;
                            if(!result.TextEntry) {
                                try {result.TextEntry=Object.Equals(e.GetCurrentPropertyValue(AutomationElement.IsTextPatternAvailableProperty,true),true);}
                                catch(Exception) {}
                            }
                        }
                    }
                    if(readEditable && sameForeground) {
                        result.Editable=e!=null && result.Usable && e.Current.IsEnabled && e.Current.HasKeyboardFocus && IsEditable(e);
                        result.Bounds=Rectangle.Intersect(result.Bounds,N.Bounds(fg));
                        result.Usable=result.Usable && Geo.Area(result.Bounds)>0;
                        // Never attribute a delayed UIA response to a different foreground window.
                        result.Confirmed=N.GetForegroundWindow()==fg;
                    }
                } catch(Exception) { /* A missing, elevated or hung provider must not block the UI thread. */ }
                lock(gate) { if(stopping) return; latest=result; }
            }
        }
        public void Dispose() {
            lock(gate) stopping=true;
            wake.Set();
            // A foreign provider can hang. Never wait for it on the UI thread or abort it.
            // Background thread and wait handle are reclaimed when this dedicated process exits.
        }
    }

    internal static class Hotkey {
        internal static bool Parse(string text,out uint modifiers,out uint key) {
            modifiers=0x4000; key=0; // MOD_NOREPEAT
            if(String.IsNullOrWhiteSpace(text)) return false;
            string[] tokens=text.Split('+');
            foreach(string raw in tokens) {
                string t=raw.Trim().ToUpperInvariant();
                if(t=="CTRL" || t=="CONTROL") modifiers|=2;
                else if(t=="ALT") modifiers|=1;
                else if(t=="SHIFT") modifiers|=4;
                else if(t=="WIN") modifiers|=8;
                else {
                    if(key!=0) return false;
                    Keys k;
                    if(!Enum.TryParse<Keys>(t,true,out k) || (int)k<=0 || (int)k>255) return false;
                    key=(uint)k;
                }
            }
            return key!=0 && (modifiers&15)!=0;
        }
    }
    internal sealed class Hamburger : OverlayForm {
        readonly Controller owner;
        internal readonly Screen Display;
        bool hover;
        internal Hamburger(Controller controller,Screen screen) {
            owner=controller;Display=screen;
            FormBorderStyle=FormBorderStyle.None; ShowInTaskbar=false; StartPosition=FormStartPosition.Manual;
            AutoScaleMode=AutoScaleMode.None; TopMost=true; BackColor=Color.FromArgb(10,10,10); Cursor=Cursors.Hand;
            SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);
            MouseEnter+=delegate{hover=true;Invalidate();}; MouseLeave+=delegate{hover=false;Invalidate();};
            MouseUp+=delegate(object sender,MouseEventArgs e) {
                if(e.Button==MouseButtons.Left) owner.OpenMenu();
                else if(e.Button==MouseButtons.Right) owner.TogglePause();
            };
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams { get { CreateParams p=base.CreateParams;p.ExStyle|=0x08000080;return p; } }
        protected override void WndProc(ref Message m) { if(m.Msg==0x21){m.Result=new IntPtr(3);return;}base.WndProc(ref m); }
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e); int b=hover?230:owner.Config.HamburgerBrightness;
            using(Pen p=new Pen(Color.FromArgb(b,b,b),Math.Max(1,ClientSize.Width/15f))) {
                for(int i=0;i<3;i++) {float y=ClientSize.Height*(0.32f+0.18f*i); e.Graphics.DrawLine(p,ClientSize.Width*.23f,y,ClientSize.Width*.77f,y);}
            }
        }
        internal void Place(double percent) {
            if(!Display.Bounds.Contains(Location))Location=Display.WorkingArea.Location;
            uint dpi=N.GetDpiForWindow(Handle); double scale=dpi==0?1:dpi/96.0;
            int size=(int)Math.Round(owner.Config.HamburgerSize*scale);
            Rectangle work=Display.WorkingArea;
            int x=owner.Config.HamburgerLeft?work.Left+2:work.Right-size-2;
            int y=work.Top+(int)((work.Height-size)*percent/100.0);
            Bounds=new Rectangle(x,y,size,size); Invalidate();
        }
        internal bool NearMouse(Point p) { Rectangle b=Bounds;b.Inflate(50,50);return b.Contains(p); }
    }

    internal sealed class Controller : Form {
        internal Settings Config;
        internal readonly string ConfigPath;
        internal bool Paused;
        internal IntPtr LastApp;
        internal string LastAppProcess="";
        internal string Status="Uruchamianie";
        readonly HashSet<IntPtr> surfaces=new HashSet<IntPtr>();
        readonly List<Curtain> curtains=new List<Curtain>();
        readonly List<Hamburger> buttons=new List<Hamburger>();
        readonly WindowReader reader;
        readonly FocusWorker focus=new FocusWorker();
        readonly FocusState focusState=new FocusState();
        readonly ActiveFieldWatcher activeField=new ActiveFieldWatcher();
        readonly TaskbarYield taskbarYield=new TaskbarYield();
        readonly Stopwatch clock=Stopwatch.StartNew();
        readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
        readonly Random random=new Random();
        readonly Dictionary<int,string> registered=new Dictionary<int,string>();
        readonly List<IntPtr> eventHooks=new List<IntPtr>();
        readonly N.HookProc keyboardCallback;
        readonly N.WinEventProc eventCallback;
        IntPtr keyboardHook;
        NotifyIcon tray;
        SettingsForm menu;
        Screen[] screens;
        Layout layout=new Layout();
        string screenSignature="";
        Point mouse;
        double lastMouse=0,lastKey=-100000,nextScan=0,nextScreens=0,nextButtonMove=0;
        double revealUntil=0,altMenuUntil=0,saveAt=Double.MaxValue,lastFocusRequest=-100000;
        double focusRequestDue=0;
        int focusSequence=0;
        bool focusChanged=false;
        bool requireFocus=false,switching=false,refresh=true,stopping=false;
        double switchStarted=0;
        string dirtySettingsError="";
        internal Controller(Settings settings,string path,bool paused) {
            Config=settings;ConfigPath=path;Paused=paused;
            FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;Size=new Size(1,1);Location=new Point(-32000,-32000);
            reader=new WindowReader(surfaces);
            keyboardCallback=Keyboard;eventCallback=WinEvent;
        }
        internal void Initialize() {
            IntPtr handle=Handle;surfaces.Add(handle);
            string error; bool keysOk=RegisterKeys(Config,out error);
            if(!keysOk)Paused=true;
            keyboardHook=N.SetWindowsHookEx(13,keyboardCallback,N.GetModuleHandle(null),0);
            eventHooks.Add(N.SetWinEventHook(3,3,IntPtr.Zero,eventCallback,0,0,2)); // foreground
            eventHooks.Add(N.SetWinEventHook(0x14,0x15,IntPtr.Zero,eventCallback,0,0,2)); // switch start/end
            eventHooks.Add(N.SetWinEventHook(0x8005,0x8007,IntPtr.Zero,eventCallback,0,0,2)); // focus/selection
            eventHooks.Add(N.SetWinEventHook(0x800B,0x800B,IntPtr.Zero,eventCallback,0,0,2)); // window moved
            tray=new NotifyIcon {Icon=SystemIcons.Application,Text="FocusShade 2.0.4",Visible=true};
            ContextMenuStrip context=new ContextMenuStrip();
            context.Items.Add("Ustawienia",null,delegate{OpenMenu();});
            context.Items.Add("Pauza / wznów",null,delegate{TogglePause();});
            context.Items.Add("Zakończ",null,delegate{Shutdown();});
            tray.ContextMenuStrip=context; tray.DoubleClick+=delegate{OpenMenu();};
            N.POINT p;N.GetCursorPos(out p);mouse=new Point(p.X,p.Y);
            timer.Interval=Math.Max(11,1000/Config.FramesPerSecond);timer.Tick+=Tick;
            RebuildScreens();timer.Start();
            if(!keysOk)BeginInvoke((MethodInvoker)delegate{
                MessageBox.Show(error+"\nUruchomiono w pauzie. Zmień skróty w sekcji Zaawansowane.","FocusShade",MessageBoxButtons.OK,MessageBoxIcon.Warning);
                OpenMenu();
            });
            if(keyboardHook==IntPtr.Zero) {
                Status="Brak haka klawiatury; skróty globalne nadal działają";
                tray.ShowBalloonTip(6000,"FocusShade",Status,ToolTipIcon.Warning);
            }
        }
        protected override bool ShowWithoutActivation {get{return true;}}
        protected override void SetVisibleCore(bool value) {base.SetVisibleCore(false);}
        protected override void WndProc(ref Message m) {
            if(m.Msg==0x312) {
                switch(m.WParam.ToInt32()) {
                    case 1:TogglePause();break;case 2:OpenMenu();break;case 3:Shutdown();break;
                    case 4:AdjustTop(4);break;case 5:AdjustTop(-4);break;
                }
            }
            if(m.Msg==0x7E || m.Msg==0x2E0) nextScreens=0;
            base.WndProc(ref m);
        }
        internal bool RegisterKeys(Settings s,out string error) {
            error="";
            string[] candidates={s.PauseHotkey,s.MenuHotkey,s.ExitHotkey,s.RaiseTopHotkey,s.LowerTopHotkey};
            HashSet<string> unique=new HashSet<string>();
            for(int i=0;i<candidates.Length;i++) {
                uint mod,key;
                if(!Hotkey.Parse(candidates[i],out mod,out key) || !unique.Add(mod+":"+key)) {error="Nieprawidłowy lub powtórzony skrót: "+candidates[i];return false;}
            }
            Dictionary<int,string> before=new Dictionary<int,string>(registered);
            foreach(int id in registered.Keys) N.UnregisterHotKey(Handle,id);registered.Clear();
            for(int i=0;i<candidates.Length;i++) {
                uint mod,key;Hotkey.Parse(candidates[i],out mod,out key);
                if(!N.RegisterHotKey(Handle,i+1,mod,key)) {
                    error="Skrót jest zajęty lub niedostępny: "+candidates[i];
                    foreach(int id in registered.Keys) N.UnregisterHotKey(Handle,id);registered.Clear();
                    foreach(KeyValuePair<int,string> pair in before) {
                        Hotkey.Parse(pair.Value,out mod,out key);
                        if(N.RegisterHotKey(Handle,pair.Key,mod,key)) registered[pair.Key]=pair.Value;
                    }
                    return false;
                }
                registered[i+1]=candidates[i];
            }
            return true;
        }
        void RebuildScreens() {
            taskbarYield.Reset();
            foreach(Hamburger b in buttons) {surfaces.Remove(b.Handle);b.Dispose();}buttons.Clear();
            foreach(Curtain c in curtains) {surfaces.Remove(c.Handle);c.Dispose();}curtains.Clear();
            screens=Screen.AllScreens;
            // One surface per distinct desktop rectangle; mirroring must not stack the opacity.
            foreach(Screen s in screens.GroupBy(x=>x.Bounds).Select(x=>x.First())) {
                Curtain c=new Curtain(s);curtains.Add(c);surfaces.Add(c.Handle);
                Hamburger b=new Hamburger(this,s);buttons.Add(b);surfaces.Add(b.Handle);
                b.Place(Config.HamburgerPositionPercent);
            }
            screenSignature=String.Join(";",screens.Select(x=>x.DeviceName+":"+x.Bounds+":"+x.WorkingArea));
            nextButtonMove=clock.Elapsed.TotalSeconds+Config.HamburgerMoveSeconds;refresh=true;nextScan=0;
        }
        void WinEvent(IntPtr hook,uint ev,IntPtr h,int obj,int child,uint tid,uint stamp) {
            double now=clock.Elapsed.TotalSeconds;
            if(ev==0x14) {switching=true;switchStarted=now;}
            else if(ev==0x15) {switching=false;revealUntil=Math.Max(revealUntil,now+0.4);}
            else if(ev==3) {nextScan=0;altMenuUntil=0;}
            else if(ev==0x8005) {
                // Some editors emit focus-like events while changing the caret/selection.
                // Explicit navigation has already requested a real focus change in Keyboard().
                if(lastKey>lastMouse)QueueFocus(now,!focusState.Editing);
            } else if(ev==0x8006 || ev==0x8007) {
                // Text selection/caret changes do not move the focused editing control.
                if(lastKey>lastMouse && !focusState.Editing)QueueFocus(now,false);
            } else if(ev==0x800B && obj==0 && !surfaces.Contains(h)) {
                nextScan=0;
                if(lastKey>lastMouse && h==focusState.Foreground)QueueFocus(now,false);
            }
        }
        void QueueFocus(double now,bool actualFocusChange) {
            if(!requireFocus)focusRequestDue=now+0.035;
            requireFocus=true;focusChanged|=actualFocusChange;
        }
        IntPtr Keyboard(int n,IntPtr wp,IntPtr lp) {
            if(n>=0 && !stopping) {
                N.KBD k=(N.KBD)Marshal.PtrToStructure(lp,typeof(N.KBD));
                int message=wp.ToInt32(),vk=(int)k.vk;
                if(message==0x100 || message==0x104) {
                    double now=clock.Elapsed.TotalSeconds;
                    bool win=vk==91||vk==92||N.Down(91)||N.Down(92), alt=vk==18||vk==164||vk==165||N.Down(18);
                    bool control=N.Down(17);
                    bool altGr=vk==165 || N.Down(165) || (control && alt);
                    if(win || (alt&&(vk==9 || vk==27))) revealUntil=Math.Max(revealUntil,now+1.2);
                    if((vk==18 || vk==164 || vk==121) && !control && !altGr) altMenuUntil=now+4;
                    if(vk==27) {altMenuUntil=0;switching=false;}
                    else if(altMenuUntil>now) altMenuUntil=now+4;
                    IntPtr fg=N.GetForegroundWindow();
                    if(focusState.Foreground!=fg) {
                        focusState.Reset(fg);focusChanged=false;requireFocus=false;
                        if(lastKey>lastMouse)QueueFocus(now,true);
                    }
                    bool navigation=KeyboardPolicy.Navigate(vk,control,alt,win,altGr,layout.Desktop,focusState.Editing);
                    if(navigation) {
                        lastKey=now;focusState.Navigate(now,Config.KeyboardFallbackSeconds);QueueFocus(now,true);
                        if(Config.RevealActiveField)activeField.FocusMayChange(now,false);
                    } else if(!KeyboardPolicy.Modifier(vk) && lastKey>lastMouse) {
                        // Keep a keyboard spotlight alive while typing, without replacing it for every letter.
                        lastKey=now;focusState.Typing();
                    }
                }
            }
            return N.CallNextHookEx(keyboardHook,n,wp,lp);
        }
        internal void Changed(bool immediate) {
            Config.Normalize();refresh=true;nextScan=0;
            timer.Interval=Math.Max(11,1000/Config.FramesPerSecond);
            if(immediate) Save();else saveAt=clock.Elapsed.TotalSeconds+0.6;
            foreach(Hamburger b in buttons) b.Place(Config.HamburgerPositionPercent);
        }
        internal bool Save() {
            saveAt=Double.MaxValue;
            try {Config.Save(ConfigPath);dirtySettingsError="";return true;}
            catch(Exception e) {
                if(dirtySettingsError!=e.Message) {
                    dirtySettingsError=e.Message;tray.ShowBalloonTip(6000,"Nie zapisano ustawień",e.Message,ToolTipIcon.Error);
                }
                return false;
            }
        }
        internal void TogglePause() {Paused=!Paused;refresh=true;nextScan=0;if(menu!=null)menu.UpdateStatus();}
        internal void OpenMenu() {
            if(stopping) return;
            if(menu!=null && !menu.IsDisposed) {menu.Show();menu.Activate();return;}
            menu=new SettingsForm(this);menu.FormClosed+=delegate{menu=null;refresh=true;nextScan=0;};
            menu.Show();menu.Activate();refresh=true;nextScan=0;
        }
        void AdjustTop(int delta) {
            if(String.IsNullOrEmpty(LastAppProcess)) return;
            Profile p=Config.For(LastAppProcess).Copy();p.Top=Math.Max(0,Math.Min(2000,p.Top+delta));
            Config.Profiles[LastAppProcess]=p;Changed(false);
            if(menu!=null) menu.RefreshProfile();
        }
        void Tick(object sender,EventArgs unused) {
            if(stopping) return;
            try {UpdateFrame();}
            catch(Exception e) {
                timer.Stop();
                foreach(Curtain c in curtains)c.Suspend();foreach(Hamburger b in buttons)b.Hide();
                Entry.Log(ConfigPath,e);
                MessageBox.Show("Kurtyna została wyłączona po błędzie.\n\n"+e.Message,"FocusShade",MessageBoxButtons.OK,MessageBoxIcon.Error);
                Shutdown();
            }
        }
        void UpdateFrame() {
            double now=clock.Elapsed.TotalSeconds;
            if(now>=saveAt)Save();
            N.POINT pos;N.GetCursorPos(out pos);Point point=new Point(pos.X,pos.Y);
            if(point!=mouse || N.Down(1) || N.Down(2)) {
                mouse=point;lastMouse=now;altMenuUntil=0;
                focusState.Reset(IntPtr.Zero);requireFocus=false;focusChanged=false;
            }
            if(now>=nextScreens) {
                Screen[] all=Screen.AllScreens;
                string sig=String.Join(";",all.Select(x=>x.DeviceName+":"+x.Bounds+":"+x.WorkingArea));
                if(sig!=screenSignature)RebuildScreens();
                nextScreens=now+1.5;
            }
            IntPtr foreground=N.GetForegroundWindow();
            if(focusState.Foreground!=foreground) {
                focusState.Reset(foreground);requireFocus=false;focusChanged=false;
                if(lastKey>lastMouse)QueueFocus(now,true);
            }
            if(now>=nextScan || refresh) {
                uint p;N.GetWindowThreadProcessId(foreground,out p);
                string cls=N.Class(foreground),process=reader.ProcessName(foreground);
                if(p!=Process.GetCurrentProcess().Id && !N.Desktop(cls) && !N.ShellUI(cls,process) &&
                    cls!="Shell_TrayWnd" && cls!="Shell_SecondaryTrayWnd" && foreground!=IntPtr.Zero) {
                    LastApp=foreground;LastAppProcess=process;
                }
                Layout next=reader.Read(Config,screens,foreground,LastApp);
                if(refresh || next.Signature!=layout.Signature) {
                    foreach(Curtain c in curtains)c.Rebuild(next,Config);
                    refresh=false;
                }
                layout=next;nextScan=now+Config.WindowScanMs/1000.0;
            }
            if(switching && now-switchStarted>30 && !N.Down(18))switching=false;
            bool temporary=layout.Shell || layout.NativeMenu || now<revealUntil || now<altMenuUntil || switching || N.Down(91) || N.Down(92);
            activeField.Tick(now,foreground,point,N.Down(1)||N.Down(2),Config.RevealActiveField && !Paused && !temporary && (menu==null || !menu.ContainsFocus));
            bool fromKeyboard=Config.KeyboardFocus && lastKey>lastMouse && (menu==null || !menu.ContainsFocus);
            focusState.Observe(focus.Result,now);
            // A low-rate refresh follows resized/moving text fields without tying queries to keystrokes.
            if(fromKeyboard && focusState.Editing && !focusState.Pending && now-lastFocusRequest>=0.75 && now-lastKey<Config.MouseIdleSeconds)
                QueueFocus(now,false);
            if(fromKeyboard && requireFocus && now>=focusRequestDue && now-lastFocusRequest>=0.10) {
                focusState.Begin(++focusSequence,now,focusChanged);
                focus.Request(focusSequence,foreground);lastFocusRequest=now;requireFocus=false;focusChanged=false;
            }
            double age=now-(fromKeyboard?lastKey:lastMouse);
            Spot spot=new Spot {Center=mouse,Strength=Spot.FadeStrength(age,Config.MouseIdleSeconds,Config.FadeSeconds)};
            Screen current=Screen.FromPoint(spot.Center);
            if(fromKeyboard) {
                FocusResult result=focusState.Current;
                bool usable=result!=null && result.Foreground==foreground && result.Usable;
                bool knownLocation=Geo.Area(activeField.Bounds(now))>0;
                bool covered=true;
                if(usable) {
                    Rectangle r=result.Bounds;
                    Point center=new Point(r.Left+r.Width/2,r.Top+r.Height/2);
                    current=Screen.FromPoint(center);
                    usable=current.Bounds.IntersectsWith(r);
                    if(usable) {
                        covered=curtains.Any(c=>c.AlphaAt(center)>0);
                        knownLocation=true;
                        bool small=r.Width<current.Bounds.Width*.65 && r.Height<current.Bounds.Height*.55;
                        if(result.WideInput && r.Width>current.Bounds.Width*Config.DiameterPercent/100 && r.Height<current.Bounds.Height*.30) {
                            spot.Center=center;spot.FocusRect=Rectangle.Inflate(r,5,4);
                        } else if(small) spot.Center=center;
                        else {usable=false;knownLocation=!covered;if(!covered)spot.Strength=0;}
                    }
                }
                if(!usable) {
                    spot.Strength=0;
                }
                if(focusState.Fallback(now,Config.KeyboardFallbackSeconds,knownLocation))temporary=true;
            }
            spot.Radius=Math.Max(8,(int)Math.Round(current.Bounds.Width*Config.DiameterPercent/200));
            if(spot.Strength==0)spot.FocusRect=Rectangle.Empty;
            spot.ActiveFields=ActiveFieldGeometry.Visible(activeField.Bounds(now),foreground,layout.Windows);
            bool anyFull=layout.Fullscreen.Count>0;
            Status=Paused?"Pauza":temporary?"Odsłonięcie na czas obsługi":anyFull?"Pełny ekran: odsłonięty monitor":"Kurtyna działa";
            for(int i=0;i<curtains.Count;i++) {
                Curtain c=curtains[i];Hamburger b=buttons[i];bool full=layout.Fullscreen.Contains(c.Display.DeviceName);
                bool curtainWasVisible=c.Visible;
                bool taskbar=taskbarYield.Active(c.Display.DeviceName,
                    TaskbarYield.Requested(c.Display.Bounds,point,layout.Taskbars),now);
                if(Paused || temporary || full || taskbar)c.Suspend();
                else c.Render(spot,Config);
                // TopMost already keeps the curtain above ordinary applications.
                // Reasserting HWND_TOPMOST on each scan fights Explorer and other overlays.
                bool showButton=Config.ShowHamburger && !temporary && !full && !taskbar;
                if(showButton) {
                    bool first=!b.Visible;if(first)b.Show();
                    // Only restore our own button above a newly shown curtain (e.g. unpause).
                    // A newly shown button is already above it; no periodic Z-order changes.
                    if(!first && !curtainWasVisible && c.Visible)
                        N.SetWindowPos(b.Handle,N.Topmost,0,0,0,0,0x213);
                } else if(b.Visible)b.Hide();
            }
            if(now>=nextButtonMove) {
                if(Config.MoveHamburger && menu==null)foreach(Hamburger b in buttons)if(!b.NearMouse(mouse))b.Place(15+random.NextDouble()*70);
                nextButtonMove=now+Config.HamburgerMoveSeconds;
            }
            if(menu!=null)menu.UpdateStatus();
        }
        internal void Shutdown() { if(stopping)return;stopping=true;timer.Stop();if(saveAt<Double.MaxValue)Save();Close(); }
        protected override void Dispose(bool disposing) {
            stopping=true;
            if(disposing) {
                timer.Stop();timer.Dispose();focus.Dispose();activeField.Dispose();
                if(menu!=null)menu.Dispose();
                foreach(int id in registered.Keys)N.UnregisterHotKey(Handle,id);registered.Clear();
                if(keyboardHook!=IntPtr.Zero){N.UnhookWindowsHookEx(keyboardHook);keyboardHook=IntPtr.Zero;}
                foreach(IntPtr h in eventHooks)if(h!=IntPtr.Zero)N.UnhookWinEvent(h);eventHooks.Clear();
                if(tray!=null){tray.Visible=false;if(tray.ContextMenuStrip!=null)tray.ContextMenuStrip.Dispose();tray.Dispose();tray=null;}
                foreach(Hamburger b in buttons)b.Dispose();buttons.Clear();
                foreach(Curtain c in curtains)c.Dispose();curtains.Clear();
            }
            base.Dispose(disposing);
        }
    }

    internal sealed class SettingsForm : Form {
        readonly Controller owner;
        readonly FlowLayoutPanel stack=new FlowLayoutPanel();
        readonly Label status=new Label();
        readonly ToolTip tips=new ToolTip();
        readonly ComboBox profiles=new ComboBox();
        readonly Dictionary<string,NumericUpDown> profileNumbers=new Dictionary<string,NumericUpDown>();
        readonly CheckBox always=new CheckBox();
        readonly Dictionary<string,TextBox> keys=new Dictionary<string,TextBox>();
        bool loading;
        internal SettingsForm(Controller controller) {
            owner=controller; Text="FocusShade — ustawienia";Font=new Font("Segoe UI",9f);
            StartPosition=FormStartPosition.Manual;AutoScaleDimensions=new SizeF(96,96);AutoScaleMode=AutoScaleMode.Dpi;
            ClientSize=new Size(630,760);MinimumSize=new Size(480,400);TopMost=true;
            BackColor=Color.FromArgb(35,35,38);ForeColor=Color.Gainsboro;
            Panel scroll=new Panel {Dock=DockStyle.Fill,AutoScroll=true,Padding=new Padding(12)};
            stack.FlowDirection=FlowDirection.TopDown;stack.WrapContents=false;stack.AutoSize=true;
            stack.AutoSizeMode=AutoSizeMode.GrowAndShrink;stack.Dock=DockStyle.Top;
            scroll.Controls.Add(stack);Controls.Add(scroll);
            status.AutoSize=true;status.Margin=new Padding(5,4,5,12);stack.Controls.Add(status);
            TableLayoutPanel main=Group("Główne");
            AddNumber(main,"Prześwit kurtyny (%)",owner.Config.CurtainTransmission,0,100,1,0,v=>owner.Config.CurtainTransmission=v,
                "0% = pełna czerń; 100% = całkowite odsłonięcie. Zmiany są widoczne od razu.");
            AddNumber(main,"Prześwit pasków (%)",owner.Config.PanelTransmission,0,100,1,0,v=>owner.Config.PanelTransmission=v,null);
            AddNumber(main,"Latarka: bezczynność (sekundy)",owner.Config.MouseIdleSeconds,1,86400,5,0,v=>owner.Config.MouseIdleSeconds=v,null);
            AddNumber(main,"Średnica latarki (% szerokości)",owner.Config.DiameterPercent,2,100,.5,1,v=>owner.Config.DiameterPercent=v,"16,7% to około 1/6 szerokości monitora.");
            AddNumber(main,"Dopuszczalne zasłonięcie okna (%)",owner.Config.MaxOcclusionPercent,0,99,1,0,v=>owner.Config.MaxOcclusionPercent=v,
                "Okno aktywne jest odsłonięte zawsze. Pozostałe, jeśli łączny zakryty obszar roboczy nie przekracza tego progu.");
            AddCheck(main,"Pauza na monitorze z pełnym ekranem",owner.Config.PauseFullscreen,v=>owner.Config.PauseFullscreen=v);
            TableLayoutPanel profile=Group("Profil programu — wymiary od krawędzi okna");
            profiles.DropDownStyle=ComboBoxStyle.DropDownList;profiles.Width=210;
            foreach(string name in owner.Config.Profiles.Keys.OrderBy(x=>x))profiles.Items.Add(name);
            AddRow(profile,"Proces (bez .exe)",profiles);
            profiles.SelectedIndexChanged+=delegate{RefreshProfile();};
            Button use=Button("Profil ostatnio aktywnego programu",delegate{UseLastApp();});
            AddFullRow(profile,use);
            Label note=Note("Wartości są w pikselach przy skali 100%; skrypt uwzględnia DPI.\n* = profil domyślny. Word/Foxit/Inkscape/Brave wymagają dopasowania do Twojego układu.");
            AddFullRow(profile,note);
            foreach(string side in new[]{"Top","Bottom","Left","Right"}) {
                string key=side;
                string label=side=="Top"?"Góra":side=="Bottom"?"Dół":side=="Left"?"Lewy bok":"Prawy bok";
                NumericUpDown n=Number(0,0,2000,2,0);
                profileNumbers[side]=n;AddRow(profile,label,n);
                n.ValueChanged+=delegate{if(!loading){SetProfileNumber(key,(int)n.Value);owner.Changed(false);}};
            }
            always.Text="Zawsze odsłaniaj całe okno tego programu";always.AutoSize=true;
            always.CheckedChanged+=delegate{if(!loading && CurrentProfile!=null){CurrentProfile.AlwaysReveal=always.Checked;owner.Changed(false);}};
            AddFullRow(profile,always);
            if(!String.IsNullOrEmpty(owner.LastAppProcess))UseLastApp();else profiles.SelectedItem="*";

            Button expand=Button("Zaawansowane ▸",null);stack.Controls.Add(expand);
            TableLayoutPanel advanced=Group("Zaawansowane");advanced.Parent.Visible=false;
            expand.Click+=delegate{advanced.Parent.Visible=!advanced.Parent.Visible;expand.Text=advanced.Parent.Visible?"Zaawansowane ▾":"Zaawansowane ▸";};
            AddNumber(advanced,"Jasny środek (% promienia)",owner.Config.SolidCenterPercent,0,95,5,0,v=>owner.Config.SolidCenterPercent=v,null);
            AddNumber(advanced,"Czas wygaszania latarki (s)",owner.Config.FadeSeconds,0,10,.1,1,v=>owner.Config.FadeSeconds=v,null);
            AddNumber(advanced,"Klatki na sekundę",owner.Config.FramesPerSecond,10,90,5,0,v=>owner.Config.FramesPerSecond=(int)v,
                "Wyższa wartość = płynniejszy ruch i większe obciążenie. Nieruchoma kurtyna nie jest rysowana ponownie.");
            AddNumber(advanced,"Sprawdzanie okien (ms)",owner.Config.WindowScanMs,75,2000,25,0,v=>owner.Config.WindowScanMs=(int)v,null);
            AddCheck(advanced,"Pełny ekran odsłania wszystkie monitory",owner.Config.FullscreenAllMonitors,v=>owner.Config.FullscreenAllMonitors=v);
            AddCheck(advanced,"Latarka za fokusem klawiatury",owner.Config.KeyboardFocus,v=>owner.Config.KeyboardFocus=v);
            AddCheck(advanced,"Odsłaniaj aktywne pole tekstowe",owner.Config.RevealActiveField,v=>owner.Config.RevealActiveField=v);
            AddNumber(advanced,"Awaryjne odsłonięcie po klawiaturze (s)",owner.Config.KeyboardFallbackSeconds,1,60,1,0,v=>owner.Config.KeyboardFallbackSeconds=v,
                "Czas odsłonięcia, gdy nie uda się ustalić położenia elementu wybranego klawiaturą.");
            AddCheck(advanced,"Pokaż hamburger",owner.Config.ShowHamburger,v=>owner.Config.ShowHamburger=v);
            AddCheck(advanced,"Hamburger przy lewej krawędzi",owner.Config.HamburgerLeft,v=>owner.Config.HamburgerLeft=v);
            AddCheck(advanced,"Okresowo przesuwaj hamburger",owner.Config.MoveHamburger,v=>owner.Config.MoveHamburger=v);
            AddNumber(advanced,"Położenie hamburgera (% wysokości)",owner.Config.HamburgerPositionPercent,5,95,5,0,v=>owner.Config.HamburgerPositionPercent=v,null);
            AddNumber(advanced,"Przesuwanie hamburgera co (s)",owner.Config.HamburgerMoveSeconds,15,86400,15,0,v=>owner.Config.HamburgerMoveSeconds=(int)v,null);
            AddNumber(advanced,"Rozmiar hamburgera",owner.Config.HamburgerSize,18,64,2,0,v=>owner.Config.HamburgerSize=(int)v,null);
            AddNumber(advanced,"Jasność kresek (30–255)",owner.Config.HamburgerBrightness,30,255,5,0,v=>owner.Config.HamburgerBrightness=(int)v,null);
            AddKey(advanced,"Pauza / wznowienie","PauseHotkey",owner.Config.PauseHotkey);
            AddKey(advanced,"Otwórz ustawienia","MenuHotkey",owner.Config.MenuHotkey);
            AddKey(advanced,"Zakończ","ExitHotkey",owner.Config.ExitHotkey);
            AddKey(advanced,"Zwiększ górny pas o 4 px","RaiseTopHotkey",owner.Config.RaiseTopHotkey);
            AddKey(advanced,"Zmniejsz górny pas o 4 px","LowerTopHotkey",owner.Config.LowerTopHotkey);
            AddFullRow(advanced,Button("Zastosuj skróty",ApplyKeys));
            AddFullRow(advanced,Button("Otwórz plik ustawień",delegate{if(owner.Save())Process.Start("notepad.exe","\""+owner.ConfigPath+"\"");}));
            AddFullRow(advanced,Note("Zmiany w menu zapisują się automatycznie.\nPo ręcznej edycji pliku ustawień uruchom skrypt ponownie."));
            FlowLayoutPanel actions=new FlowLayoutPanel {AutoSize=true,WrapContents=true,MaximumSize=new Size(580,0)};
            actions.Controls.Add(Button("Pauza / wznów",delegate{owner.TogglePause();}));
            actions.Controls.Add(Button("Zamknij menu",delegate{Close();}));
            actions.Controls.Add(Button("Zakończ FocusShade",delegate{owner.Shutdown();}));
            stack.Controls.Add(actions);
            FormClosing+=delegate{owner.Save();};
            Load+=delegate {
                Screen s=Screen.FromPoint(Cursor.Position);Rectangle work=s.WorkingArea;
                Location=new Point(work.Left+15,work.Top+15);
                uint dpi=N.GetDpiForWindow(Handle);double scale=dpi==0?1:dpi/96.0;
                Size=new Size(Math.Min((int)(650*scale),work.Width-30),Math.Min((int)(810*scale),work.Height-30));
                Location=new Point(work.Left+(work.Width-Width)/2,work.Top+(work.Height-Height)/2);
                owner.Changed(false);
            };
            UpdateStatus();
        }
        internal void UpdateStatus() {
            string text=owner.Status+(String.IsNullOrEmpty(owner.LastAppProcess)?"":"  |  "+owner.LastAppProcess+".exe");
            if(status.Text!=text)status.Text=text;
        }
        static Button Button(string text,Action click) {
            Button b=new Button {Text=text,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,Padding=new Padding(7,4,7,4),Margin=new Padding(4),UseVisualStyleBackColor=true,ForeColor=Color.Black};
            if(click!=null)b.Click+=delegate{click();};return b;
        }
        static Label Note(string text) {return new Label {Text=text,AutoSize=true,MaximumSize=new Size(550,0),Margin=new Padding(5,8,5,8)};}
        TableLayoutPanel Group(string title) {
            GroupBox group=new GroupBox {Text=title,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,Padding=new Padding(10,22,10,10),ForeColor=ForeColor,Margin=new Padding(0,0,0,12)};
            TableLayoutPanel table=new TableLayoutPanel {ColumnCount=2,AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,Dock=DockStyle.Fill};
            table.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));table.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            group.Controls.Add(table);stack.Controls.Add(group);return table;
        }
        static NumericUpDown Number(double value,double min,double max,double step,int decimals) {
            return new NumericUpDown {Minimum=(decimal)min,Maximum=(decimal)max,Value=(decimal)Settings.Clamp(value,min,max),
                Increment=(decimal)step,DecimalPlaces=decimals,Width=112,Margin=new Padding(5),ThousandsSeparator=true};
        }
        static void AddRow(TableLayoutPanel table,string text,Control control) {
            int row=table.RowCount++;table.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Label label=new Label {Text=text,AutoSize=true,MaximumSize=new Size(345,0),Anchor=AnchorStyles.Left,Margin=new Padding(5,7,14,7)};
            table.Controls.Add(label,0,row);table.Controls.Add(control,1,row);
        }
        static void AddFullRow(TableLayoutPanel table,Control control) {
            int row=table.RowCount++;table.RowStyles.Add(new RowStyle(SizeType.AutoSize));table.Controls.Add(control,0,row);table.SetColumnSpan(control,2);
        }
        void AddNumber(TableLayoutPanel table,string text,double initial,double min,double max,double step,int decimals,Action<double> change,string hint) {
            NumericUpDown n=Number(initial,min,max,step,decimals);AddRow(table,text,n);
            if(hint!=null)tips.SetToolTip(n,hint);
            n.ValueChanged+=delegate{change((double)n.Value);owner.Changed(false);};
        }
        void AddCheck(TableLayoutPanel table,string text,bool initial,Action<bool> change) {
            CheckBox c=new CheckBox {Text=text,Checked=initial,AutoSize=true,MaximumSize=new Size(560,0),Margin=new Padding(5,8,5,8)};
            AddFullRow(table,c);c.CheckedChanged+=delegate{change(c.Checked);owner.Changed(false);};
        }
        void AddKey(TableLayoutPanel table,string label,string key,string value) {
            TextBox box=new TextBox {Text=value,Width=170,Margin=new Padding(5)};keys[key]=box;AddRow(table,label,box);
        }
        void ApplyKeys() {
            Settings next=owner.Config.Copy();
            foreach(KeyValuePair<string,TextBox> p in keys)typeof(Settings).GetField(p.Key).SetValue(next,p.Value.Text.Trim());
            string error;if(!owner.RegisterKeys(next,out error)){MessageBox.Show(this,error,"Skróty",MessageBoxButtons.OK,MessageBoxIcon.Warning);return;}
            foreach(KeyValuePair<string,TextBox> p in keys)typeof(Settings).GetField(p.Key).SetValue(owner.Config,p.Value.Text.Trim());
            owner.Changed(true);
        }
        Profile CurrentProfile {get {Profile p;return profiles.SelectedItem!=null && owner.Config.Profiles.TryGetValue(profiles.SelectedItem.ToString(),out p)?p:null;}}
        void UseLastApp() {
            string process=owner.LastAppProcess;if(String.IsNullOrWhiteSpace(process))return;
            if(!owner.Config.Profiles.ContainsKey(process))owner.Config.Profiles[process]=owner.Config.For(process).Copy();
            if(!profiles.Items.Contains(process))profiles.Items.Add(process);profiles.SelectedItem=process;RefreshProfile();
        }
        internal void RefreshProfile() {
            Profile p=CurrentProfile;if(p==null)return;loading=true;
            profileNumbers["Top"].Value=p.Top;profileNumbers["Bottom"].Value=p.Bottom;
            profileNumbers["Left"].Value=p.Left;profileNumbers["Right"].Value=p.Right;always.Checked=p.AlwaysReveal;loading=false;
        }
        void SetProfileNumber(string key,int value) {Profile p=CurrentProfile;if(p!=null)typeof(Profile).GetField(key).SetValue(p,value);}
        protected override void Dispose(bool disposing) {if(disposing)tips.Dispose();base.Dispose(disposing);}
    }

    public static class Entry {
        public static void Run(string configPath,bool startPaused) {
            if(Environment.OSVersion.Platform!=PlatformID.Win32NT)throw new PlatformNotSupportedException("FocusShade wymaga Windows 11.");
            if(Thread.CurrentThread.GetApartmentState()!=ApartmentState.STA)throw new InvalidOperationException("Uruchom Windows PowerShell z parametrem -STA.");
            bool acquired=false;
            using(Mutex mutex=new Mutex(false,"Local\\FocusShade.v2")) {
                try {
                    try {acquired=mutex.WaitOne(0);}catch(AbandonedMutexException){acquired=true;}
                    if(!acquired){MessageBox.Show("FocusShade już działa. Otwórz menu przez hamburger lub skonfigurowany skrót.","FocusShade");return;}
                    IntPtr oldDpi=N.SetThreadDpiAwarenessContext(new IntPtr(-4));
                    Controller c=null;
                    try {
                        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
                        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
                        string warning;Settings config=Settings.Load(configPath,out warning);
                        if(warning!=null)MessageBox.Show(warning,"FocusShade",MessageBoxButtons.OK,MessageBoxIcon.Warning);
                        c=new Controller(config,configPath,startPaused);c.Initialize();
                        Application.Run(c);
                    } finally {if(c!=null)c.Dispose();if(oldDpi!=IntPtr.Zero)N.SetThreadDpiAwarenessContext(oldDpi);}
                } finally {if(acquired)mutex.ReleaseMutex();}
            }
        }
        internal static void Log(string configPath,Exception exception) {
            try {
                string directory=Path.GetDirectoryName(configPath);Directory.CreateDirectory(directory);
                string path=Path.Combine(directory,"errors.log");
                if(File.Exists(path) && new FileInfo(path).Length>1048576)File.Delete(path);
                File.AppendAllText(path,DateTime.Now.ToString("s")+" "+exception+Environment.NewLine,Encoding.UTF8);
            } catch(Exception) {}
        }
        public static string SelfTest() {
            int count=0;
            Action<bool,string> check=delegate(bool condition,string name){if(!condition)throw new Exception("TEST FAILED: "+name);count++;};
            Rectangle target=new Rectangle(0,0,100,100);
            Rectangle[] display={new Rectangle(0,0,200,100)};
            check(Math.Abs(Geo.VisibleFraction(target,display,new Rectangle[0])-1)<0.000001,"uncovered");
            check(Math.Abs(Geo.VisibleFraction(target,display,new[]{new Rectangle(0,0,10,100)})-.9)<0.000001,"10 percent threshold");
            check(Math.Abs(Geo.VisibleFraction(target,display,new[]{new Rectangle(0,0,10,100),new Rectangle(0,0,10,100)})-.9)<0.000001,"overlap counted once");
            check(Math.Abs(Geo.VisibleFraction(target,display,new[]{new Rectangle(0,0,6,100),new Rectangle(94,0,6,100)})-.88)<0.000001,"combined occlusion");
            check(Geo.VisibleFraction(target,display,new[]{new Rectangle(0,0,100,100)})==0,"fully hidden");
            check(Geo.VisibleFraction(target,display,new[]{new Rectangle(100,0,100,100)})==1,"side by side");
            check(Geo.VisibleFraction(target,new[]{target,target},new Rectangle[0])==1,"mirrored displays");
            check(Geo.VisibleFraction(new Rectangle(-100,0,200,100),display,new Rectangle[0])==1,"offscreen portion excluded");
            check(Geo.VisibleFraction(new Rectangle(-100,0,100,100),new[]{new Rectangle(-100,0,100,100)},new Rectangle[0])==1,"negative screen coordinates");
            check(Geo.VisibleFraction(Rectangle.Empty,display,new Rectangle[0])==0,"empty area");
            check(Geo.Work(target,new Profile{Top=20,Bottom=5,Left=5,Right=10},1.5)==Rectangle.FromLTRB(8,30,85,92),"DPI scaling");
            check(Geo.Work(target,new Profile{Top=200},1)==Rectangle.Empty,"too small client");
            uint mods,key;check(Hotkey.Parse("Ctrl+Alt+Space",out mods,out key)&&key==32&&(mods&3)==3,"hotkey parse");
            check(!Hotkey.Parse("Ctrl+Alt+NoSuchKey",out mods,out key),"invalid key");
            check(!Hotkey.Parse("Q",out mods,out key),"requires modifier");
            Settings s=new Settings();s.CurtainTransmission=200;s.MouseIdleSeconds=-1;s.Normalize();
            check(s.CurtainTransmission==100 && s.MouseIdleSeconds==1,"settings bounds");
            check(s.Copy().For("WINWORD").Top==164,"case independent profile roundtrip");
            check(Settings.NormalizeProcess("brave.exe")=="brave","process name");
            return "OK: "+count+" testów logiki. Testy nie sprawdzają wyglądu ani integracji z pulpitem Windows.";
        }
    }
}
'@
        $refs = @(
            [System.ComponentModel.Component].Assembly.Location
            [System.Linq.Enumerable].Assembly.Location
            [System.Drawing.Bitmap].Assembly.Location
            [System.Windows.Forms.Form].Assembly.Location
            [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location
            [System.Windows.Automation.AutomationElement].Assembly.Location
            [System.Windows.Automation.ControlType].Assembly.Location
            [System.Windows.Rect].Assembly.Location
        ) | Select-Object -Unique
        Add-Type -TypeDefinition $source -Language CSharp -ReferencedAssemblies $refs
    }
    if ($ValidateOnly) { 'OK: kompilacja FocusShade.'; return }
    if ($SelfTest) { [FocusShadeV2.Entry]::SelfTest(); return }
    [FocusShadeV2.Entry]::Run($ConfigPath, [bool]$StartPaused)
} catch {
    $detail = $_.Exception.GetBaseException().ToString()
    try {
        $directory = [IO.Path]::GetDirectoryName($ConfigPath)
        [IO.Directory]::CreateDirectory($directory) | Out-Null
        [IO.File]::AppendAllText((Join-Path $directory 'errors.log'), ([DateTime]::Now.ToString('s') + ' ' + $detail + [Environment]::NewLine))
    } catch { }
    if (-not $ValidateOnly -and -not $SelfTest) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.MessageBox]::Show($detail.Substring(0, [Math]::Min(2500, $detail.Length)), 'FocusShade: błąd', 'OK', 'Error') | Out-Null
        } catch { }
    }
    throw
}
