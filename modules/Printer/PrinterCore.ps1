$global:KP_Dir      = Join-Path $env:ProgramData "KATK\Printer"
$global:KP_CtlPort  = 9180
$global:KP_PortMin  = 9101
$global:KP_PortMax  = 9199
$global:KP_TaskPath = "\KATK\"
$global:KP_SrvTask  = "KATK Printer Server"
$global:KP_KeepTask = "KATK Printer Keeper"
$global:KP_FwGroup  = "KATK Printer"
$global:KP_QueueTag = "(KATK - "

if (-not ("KATKPrn.Server" -as [type])) {
Add-Type -ReferencedAssemblies System.Web.Extensions -TypeDefinition @'
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace KATKPrn
{
    public static class RawPrint
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public class DOCINFO
        {
            [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
            [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
            [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
        }
        [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool OpenPrinter(string name, out IntPtr h, IntPtr def);
        [DllImport("winspool.drv", SetLastError = true)] static extern bool ClosePrinter(IntPtr h);
        [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)] static extern int StartDocPrinter(IntPtr h, int level, [In] DOCINFO di);
        [DllImport("winspool.drv", SetLastError = true)] static extern bool EndDocPrinter(IntPtr h);
        [DllImport("winspool.drv", SetLastError = true)] static extern bool StartPagePrinter(IntPtr h);
        [DllImport("winspool.drv", SetLastError = true)] static extern bool EndPagePrinter(IntPtr h);
        [DllImport("winspool.drv", SetLastError = true)] static extern bool WritePrinter(IntPtr h, byte[] buf, int count, out int written);

        /// <summary>Gửi nguyên tệp (dữ liệu máy in đã dựng sẵn ở máy con) vào hàng đợi máy in. null = thành công.</summary>
        public static string SendFile(string printer, string docName, string path)
        {
            IntPtr h;
            if (!OpenPrinter(printer, out h, IntPtr.Zero)) return "OpenPrinter lỗi " + Marshal.GetLastWin32Error();
            try
            {
                DOCINFO di = new DOCINFO();
                di.pDocName = docName; di.pDataType = "RAW";
                if (StartDocPrinter(h, 1, di) == 0) return "StartDocPrinter lỗi " + Marshal.GetLastWin32Error();
                try
                {
                    StartPagePrinter(h);
                    using (FileStream fs = File.OpenRead(path))
                    {
                        byte[] buf = new byte[65536];
                        int r;
                        while ((r = fs.Read(buf, 0, buf.Length)) > 0)
                        {
                            int w;
                            if (!WritePrinter(h, buf, r, out w) || w != r) return "WritePrinter lỗi " + Marshal.GetLastWin32Error();
                        }
                    }
                    EndPagePrinter(h);
                }
                finally { EndDocPrinter(h); }
            }
            finally { ClosePrinter(h); }
            return null;
        }
    }

    public static class Net
    {
        public static JavaScriptSerializer Json()
        {
            JavaScriptSerializer j = new JavaScriptSerializer();
            j.MaxJsonLength = int.MaxValue;
            return j;
        }

        public static string ReadLine(Stream s, int max)
        {
            MemoryStream ms = new MemoryStream();
            while (ms.Length < max)
            {
                int b = s.ReadByte();
                if (b < 0 || b == '\n') break;
                if (b != '\r') ms.WriteByte((byte)b);
            }
            return Encoding.UTF8.GetString(ms.ToArray());
        }

        public static void WriteLine(Stream s, string line)
        {
            byte[] b = Encoding.UTF8.GetBytes(line + "\n");
            s.Write(b, 0, b.Length);
            s.Flush();
        }

        public static TcpClient Connect(string host, int port, int timeoutMs)
        {
            TcpClient c = new TcpClient(AddressFamily.InterNetwork);
            IAsyncResult ar = c.BeginConnect(host, port, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(timeoutMs)) { c.Close(); throw new TimeoutException("Không kết nối được " + host + ":" + port); }
            c.EndConnect(ar);
            c.ReceiveTimeout = 30000; c.SendTimeout = 30000;
            return c;
        }

        /// <summary>Gửi một dòng JSON tới cổng điều khiển, trả về dòng JSON trả lời.</summary>
        public static string Request(string host, int port, string json, int timeoutMs)
        {
            using (TcpClient c = Connect(host, port, timeoutMs))
            {
                NetworkStream s = c.GetStream();
                WriteLine(s, json);
                return ReadLine(s, 4 << 20);
            }
        }

        /// <summary>Tải gói driver từ máy chủ: dòng đầu {"ok":true,"size":N} rồi N byte.</summary>
        public static bool Download(string host, int port, string json, string outFile)
        {
            using (TcpClient c = Connect(host, port, 5000))
            {
                c.ReceiveTimeout = 120000;
                NetworkStream s = c.GetStream();
                WriteLine(s, json);
                Dictionary<string, object> h = Json().Deserialize<Dictionary<string, object>>(ReadLine(s, 65536));
                if (h == null || !h.ContainsKey("ok") || !(bool)h["ok"]) return false;
                long left = Convert.ToInt64(h["size"]);
                using (FileStream fs = File.Create(outFile))
                {
                    byte[] buf = new byte[65536];
                    while (left > 0)
                    {
                        int r = s.Read(buf, 0, (int)Math.Min(buf.Length, left));
                        if (r <= 0) return false;
                        fs.Write(buf, 0, r);
                        left -= r;
                    }
                }
                return true;
            }
        }

        /// <summary>Các IP trong mạng LAN của máy (mạng lớn hơn /22 thì chỉ quét /24 quanh IP máy) + 127.0.0.1.</summary>
        public static List<IPAddress> LanHosts()
        {
            List<IPAddress> list = new List<IPAddress>();
            list.Add(IPAddress.Loopback);
            foreach (NetworkInterface ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (UnicastIPAddressInformation u in ni.GetIPProperties().UnicastAddresses)
                {
                    if (u.Address.AddressFamily != AddressFamily.InterNetwork || u.IPv4Mask == null) continue;
                    byte[] a = u.Address.GetAddressBytes(), m = u.IPv4Mask.GetAddressBytes();
                    if (a[0] == 169 && a[1] == 254) continue;
                    uint ip = ((uint)a[0] << 24) | ((uint)a[1] << 16) | ((uint)a[2] << 8) | a[3];
                    uint mask = ((uint)m[0] << 24) | ((uint)m[1] << 16) | ((uint)m[2] << 8) | m[3];
                    if (mask < 0xFFFFFC00u) mask = 0xFFFFFF00u;
                    uint net = ip & mask, bc = net | ~mask;
                    for (uint h = net + 1; h < bc; h++)
                    {
                        IPAddress x = new IPAddress(new byte[] { (byte)(h >> 24), (byte)(h >> 16), (byte)(h >> 8), (byte)h });
                        if (!list.Contains(x)) list.Add(x);
                    }
                }
            }
            return list;
        }

        /// <summary>Tìm máy chủ KATK Printer: thử kết nối cổng điều khiển tới mọi IP trong mạng LAN cùng lúc
        /// (chỉ kết nối ra -> máy con không phải mở cổng / không hiện hộp tường lửa). Mỗi kết quả: "ip|json info".</summary>
        public static string[] Discover(int ctlPort, int timeoutMs)
        {
            List<TcpClient> socks = new List<TcpClient>();
            List<IAsyncResult> ars = new List<IAsyncResult>();
            List<IPAddress> ips = new List<IPAddress>();
            foreach (IPAddress ip in LanHosts())
            {
                TcpClient c = new TcpClient(AddressFamily.InterNetwork);
                try { ars.Add(c.BeginConnect(ip, ctlPort, null, null)); socks.Add(c); ips.Add(ip); } catch { c.Close(); }
            }
            DateTime end = DateTime.Now.AddMilliseconds(timeoutMs);
            List<string> open = new List<string>();
            for (int i = 0; i < socks.Count; i++)
            {
                int left = Math.Max(0, (int)(end - DateTime.Now).TotalMilliseconds);
                try { if (ars[i].AsyncWaitHandle.WaitOne(left)) { socks[i].EndConnect(ars[i]); open.Add(ips[i].ToString()); } } catch { }
                try { socks[i].Close(); } catch { }
            }
            List<string> res = new List<string>();
            Dictionary<string, int> byId = new Dictionary<string, int>();
            foreach (string ip in open)
            {
                string body;
                try { body = Request(ip, ctlPort, "{\"op\":\"info\"}", 3000); } catch { continue; }
                Dictionary<string, object> info = null;
                try { info = Json().Deserialize<Dictionary<string, object>>(body); } catch { }
                if (info == null || !info.ContainsKey("id")) continue;
                string id = Convert.ToString(info["id"]);
                // Một máy chủ trả lời qua nhiều địa chỉ (127.0.0.1 + IP LAN): giữ một dòng, ưu tiên IP LAN
                int k;
                if (byId.TryGetValue(id, out k)) { if (res[k].StartsWith("127.0.0.1|")) res[k] = ip + "|" + body; continue; }
                byId[id] = res.Count;
                res.Add(ip + "|" + body);
            }
            return res.ToArray();
        }
    }
    /// <summary>Dịch vụ máy chủ: chạy trong tác vụ "KATK Printer Server" (SYSTEM, tự chạy khi khởi động).</summary>
    public static class Server
    {
        static string _dir;
        static Dictionary<string, object> _cfg;
        static readonly object _logLock = new object(), _clientLock = new object();
        static readonly Dictionary<string, object> _printLocks = new Dictionary<string, object>();
        static ArrayList _clients = new ArrayList();
        static JavaScriptSerializer J = Net.Json();

        public static void Log(string s)
        {
            lock (_logLock)
            {
                try
                {
                    string f = Path.Combine(_dir, "server.log");
                    if (File.Exists(f) && new FileInfo(f).Length > 2 * 1024 * 1024) File.Delete(f);
                    File.AppendAllText(f, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + s + "\r\n", Encoding.UTF8);
                }
                catch { }
            }
        }

        static string Str(Dictionary<string, object> d, string k) { return d != null && d.ContainsKey(k) && d[k] != null ? Convert.ToString(d[k]) : ""; }
        static int Int(Dictionary<string, object> d, string k, int def) { try { return d != null && d.ContainsKey(k) ? Convert.ToInt32(d[k]) : def; } catch { return def; } }
        static ArrayList Printers() { return _cfg.ContainsKey("printers") && _cfg["printers"] is ArrayList ? (ArrayList)_cfg["printers"] : new ArrayList(); }

        public static void Run(string dir)
        {
            _dir = dir;
            Directory.CreateDirectory(Path.Combine(dir, "spool"));
            _cfg = J.Deserialize<Dictionary<string, object>>(File.ReadAllText(Path.Combine(dir, "server.json"), Encoding.UTF8));
            // Tệp in dở của lần chạy trước (không biết đã đủ / đã gửi chưa): bỏ, tránh in lỗi hoặc in trùng
            foreach (string f in Directory.GetFiles(Path.Combine(dir, "spool"), "*.prn")) { try { File.Delete(f); Log("Bỏ lệnh in dở của lần chạy trước: " + Path.GetFileName(f)); } catch { } }
            LoadClients();
            Log("Khởi động máy chủ " + Str(_cfg, "name") + " (" + Str(_cfg, "id") + "), " + Printers().Count + " máy in");
            foreach (object o in Printers())
            {
                Dictionary<string, object> p = (Dictionary<string, object>)o;
                string name = Str(p, "name"); int port = Int(p, "port", 0);
                if (port <= 0) continue;
                Thread t = new Thread(delegate () { DataLoop(name, port); });
                t.IsBackground = true; t.Start();
            }
            CtlLoop(Int(_cfg, "ctlPort", 9180));
        }

        static TcpListener Listen(int port, string what)
        {
            while (true)
            {
                try { TcpListener l = new TcpListener(IPAddress.Any, port); l.Start(); Log("Nghe " + what + " cổng " + port); return l; }
                catch (Exception ex) { Log("Không mở được cổng " + port + " (" + ex.Message + "), thử lại sau 15 giây"); Thread.Sleep(15000); }
            }
        }

        static void DataLoop(string printer, int port)
        {
            TcpListener l = Listen(port, "máy in \"" + printer + "\"");
            while (true)
            {
                try
                {
                    TcpClient c = l.AcceptTcpClient();
                    Thread t = new Thread(delegate () { HandleJob(c, printer, port); });
                    t.IsBackground = true; t.Start();
                }
                catch (Exception ex) { Log("Lỗi nhận lệnh in: " + ex.Message); Thread.Sleep(1000); }
            }
        }

        static void HandleJob(TcpClient c, string printer, int port)
        {
            string ip = "?", tmp = Path.Combine(Path.Combine(_dir, "spool"), Guid.NewGuid().ToString("N") + ".prn");
            long size = 0;
            try
            {
                ip = ((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString();
                c.ReceiveTimeout = 300000;
                using (c)
                using (NetworkStream s = c.GetStream())
                using (FileStream fs = File.Create(tmp))
                {
                    byte[] buf = new byte[65536];
                    int r;
                    try
                    {
                        long check = 0;
                        while ((r = s.Read(buf, 0, buf.Length)) > 0)
                        {
                            fs.Write(buf, 0, r); size += r;
                            // Mỗi 64 MB: không để lệnh in (hoặc dữ liệu rác) làm đầy ổ hệ thống
                            if (size - check >= (64L << 20))
                            {
                                check = size;
                                if (size > (4L << 30) || new DriveInfo(Path.GetPathRoot(tmp)).AvailableFreeSpace < (1L << 30))
                                { Log("Bỏ lệnh in từ " + ip + ": quá lớn hoặc ổ đĩa sắp đầy (" + size + " byte)"); size = 0; break; }
                            }
                        }
                    }
                    catch (IOException ex) { Log("Bỏ lệnh in từ " + ip + ": kết nối ngắt giữa chừng sau " + size + " byte (" + ex.Message + ")"); size = 0; }
                }
                if (size == 0) return;   // máy con chỉ dò cổng (không có dữ liệu)
                object lk;
                lock (_printLocks) { if (!_printLocks.TryGetValue(printer, out lk)) { lk = new object(); _printLocks[printer] = lk; } }
                string err;
                lock (lk)
                {
                    err = null;
                    for (int n = 1; n <= 5; n++)
                    {
                        err = RawPrint.SendFile(printer, "KATK - in từ " + ClientName(ip), tmp);
                        // Chỉ thử lại khi chưa gửi gì vào hàng đợi (tránh in trùng)
                        if (err == null || err.StartsWith("WritePrinter")) break;
                        Log("Thử lại lần " + n + ": " + err);
                        Thread.Sleep(3000);
                    }
                }
                Log((err == null ? "In OK  " : "In LỖI ") + printer + " <- " + ClientName(ip) + " " + ip + ", " + size + " byte" + (err == null ? "" : " - " + err));
                Touch(ip, printer, err == null);
            }
            catch (Exception ex) { Log("Lỗi xử lý lệnh in từ " + ip + ": " + ex.Message); }
            finally { try { File.Delete(tmp); } catch { } }
        }

        static void CtlLoop(int port)
        {
            TcpListener l = Listen(port, "điều khiển");
            while (true)
            {
                try
                {
                    TcpClient c = l.AcceptTcpClient();
                    Thread t = new Thread(delegate () { HandleCtl(c); });
                    t.IsBackground = true; t.Start();
                }
                catch (Exception ex) { Log("Lỗi cổng điều khiển: " + ex.Message); Thread.Sleep(1000); }
            }
        }

        static Dictionary<string, object> Info()
        {
            Dictionary<string, object> d = new Dictionary<string, object>();
            d["id"] = Str(_cfg, "id"); d["name"] = Str(_cfg, "name"); d["ctlPort"] = Int(_cfg, "ctlPort", 9180);
            d["printers"] = Printers();
            return d;
        }

        static void HandleCtl(TcpClient c)
        {
            string ip = "?";
            try
            {
                using (c)
                {
                    ip = ((IPEndPoint)c.Client.RemoteEndPoint).Address.ToString();
                    c.ReceiveTimeout = 15000; c.SendTimeout = 120000;
                    NetworkStream s = c.GetStream();
                    Dictionary<string, object> req = J.Deserialize<Dictionary<string, object>>(Net.ReadLine(s, 1 << 20));
                    string op = Str(req, "op");
                    if (op == "info") Net.WriteLine(s, J.Serialize(Info()));
                    else if (op == "hello") { Register(req, ip); Net.WriteLine(s, "{\"ok\":true}"); }
                    else if (op == "driver")
                    {
                        string zip = null; int port = Int(req, "port", 0);
                        foreach (object o in Printers())
                        {
                            Dictionary<string, object> p = (Dictionary<string, object>)o;
                            if (Int(p, "port", 0) == port && Str(p, "pkg").Length > 0) zip = Path.Combine(Path.Combine(_dir, "drivers"), Path.GetFileName(Str(p, "pkg")));
                        }
                        if (zip == null || !File.Exists(zip)) { Net.WriteLine(s, "{\"ok\":false}"); return; }
                        Net.WriteLine(s, "{\"ok\":true,\"size\":" + new FileInfo(zip).Length + "}");
                        using (FileStream fs = File.OpenRead(zip)) fs.CopyTo(s);
                        Log("Gửi gói driver cổng " + port + " cho " + ClientName(ip) + " " + ip);
                    }
                    else Net.WriteLine(s, "{\"ok\":false,\"error\":\"op\"}");
                }
            }
            catch (Exception ex) { Log("Lỗi yêu cầu từ " + ip + ": " + ex.Message); }
        }

        // ---- Danh sách máy con (clients.json) ----
        static void LoadClients()
        {
            try
            {
                string f = Path.Combine(_dir, "clients.json");
                if (File.Exists(f)) { object o = J.DeserializeObject(File.ReadAllText(f, Encoding.UTF8)); if (o is object[]) _clients = new ArrayList((object[])o); }
            }
            catch (Exception ex) { Log("Không đọc được clients.json: " + ex.Message); }
        }

        static void SaveClients()
        {
            try
            {
                string f = Path.Combine(_dir, "clients.json"), t = f + ".tmp";
                File.WriteAllText(t, J.Serialize(_clients), new UTF8Encoding(false));
                if (File.Exists(f)) File.Delete(f);
                File.Move(t, f);
            }
            catch (Exception ex) { Log("Không ghi được clients.json: " + ex.Message); }
        }

        static Dictionary<string, object> FindClient(string key, string val)
        {
            foreach (object o in _clients) { Dictionary<string, object> d = o as Dictionary<string, object>; if (d != null && Str(d, key) == val) return d; }
            return null;
        }

        static string ClientName(string ip)
        {
            lock (_clientLock) { Dictionary<string, object> d = FindClient("ip", ip); return d != null ? Str(d, "name") : "máy lạ"; }
        }

        static void Register(Dictionary<string, object> req, string ip)
        {
            Dictionary<string, object> cl = req.ContainsKey("client") ? req["client"] as Dictionary<string, object> : null;
            if (cl == null || Str(cl, "id").Length == 0) return;
            string now = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
            lock (_clientLock)
            {
                Dictionary<string, object> d = FindClient("id", Str(cl, "id"));
                bool isNew = d == null;
                if (isNew) { if (_clients.Count >= 500) _clients.RemoveAt(0); d = new Dictionary<string, object>(); d["firstSeen"] = now; _clients.Add(d); }
                foreach (string k in new string[] { "id", "name", "user", "arch", "os", "code" }) d[k] = Str(cl, k);
                foreach (object o in _clients) { Dictionary<string, object> x = o as Dictionary<string, object>; if (x != null && x != d && Str(x, "ip") == ip) x["ip"] = ""; }
                d["ip"] = ip; d["lastSeen"] = now;
                if (cl.ContainsKey("printers")) d["printers"] = cl["printers"];
                SaveClients();
                if (isNew || Str(req, "reason") == "connect") Log("Máy con " + Str(cl, "name") + " (" + ip + ", mã " + Str(cl, "code") + ") đã kết nối");
            }
        }

        static void Touch(string ip, string printer, bool ok)
        {
            lock (_clientLock)
            {
                Dictionary<string, object> d = FindClient("ip", ip);
                if (d == null) return;
                d["lastJob"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " · " + printer + (ok ? "" : " (lỗi)");
                d["lastSeen"] = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
                SaveClients();
            }
        }
    }
}
'@
}

function global:Get-KPArch {

    $a = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -ErrorAction SilentlyContinue).PROCESSOR_ARCHITECTURE
    switch -Regex ("$a") { 'ARM64' { 'arm64' } 'AMD64' { 'amd64' } default { 'x86' } }
}

function global:Read-KPJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function global:Write-KPJson([string]$Path, $Obj) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Obj -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

function global:Initialize-KPDir {
    if (-not (Test-Path $global:KP_Dir)) { New-Item -ItemType Directory -Force $global:KP_Dir | Out-Null }

    & icacls.exe $global:KP_Dir /inheritance:r /grant:r "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "*S-1-5-32-545:(OI)(CI)RX" 2>&1 | Out-Null
}

function global:Get-KPLanIPs {

    $ips = @()
    try {
        foreach ($c in @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })) {
            foreach ($a in @($c.IPv4Address)) { if ($a.IPAddress -notlike '169.254.*') { $ips += [pscustomobject]@{ IP = $a.IPAddress; Adapter = $c.InterfaceAlias } } }
        }
    } catch { }
    return $ips
}

function global:New-KPShortCode([string]$Guid) { return ($Guid -replace '-', '').Substring(0, 6).ToUpper() }

function global:Get-KPInfModel {

    param([string]$InfPath, [string[]]$HwIds, [string]$Arch)
    $lines = @(Get-Content -LiteralPath $InfPath -ErrorAction SilentlyContinue)
    if (-not $lines) { return $null }
    $sections = @{}; $cur = $null
    foreach ($raw in $lines) {
        $l = $raw.Trim()
        if (-not $l -or $l.StartsWith(';')) { continue }
        if ($l -match '^\[(.+)\]\s*(;.*)?$') { $cur = $Matches[1].Trim().ToLower(); if (-not $sections.ContainsKey($cur)) { $sections[$cur] = New-Object System.Collections.ArrayList }; continue }
        if ($cur) { [void]$sections[$cur].Add($l) }
    }
    $strings = @{}
    foreach ($k in @($sections.Keys | Where-Object { $_ -like 'strings*' } | Sort-Object { if ($_ -eq 'strings') { 0 } else { 1 } })) {
        foreach ($l in $sections[$k]) { if ($l -match '^([^=]+?)\s*=\s*"?(.*?)"?\s*$') { $n = $Matches[1].Trim().ToLower(); if (-not $strings.ContainsKey($n)) { $strings[$n] = $Matches[2] } } }
    }
    function Resolve-KPStr([string]$s) {
        $s = $s.Trim().Trim('"')
        if ($s -match '^%(.+)%$') { $k = $Matches[1].ToLower(); if ($strings.ContainsKey($k)) { return $strings[$k] } }
        return $s
    }
    if (-not $sections.ContainsKey('manufacturer')) { return $null }
    $want = @($HwIds | ForEach-Object { $_.ToLower() })
    foreach ($l in $sections['manufacturer']) {
        if ($l -notmatch '=\s*(.+)$') { continue }
        $parts = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() })
        $base = $parts[0]

        $decos = @($parts | Select-Object -Skip 1 | Where-Object { $_ -match "^nt$Arch(\.|$)" })
        foreach ($d in $decos) {
            $sec = ("$base.$d").ToLower()
            if (-not $sections.ContainsKey($sec)) { continue }
            foreach ($m in $sections[$sec]) {
                if ($m -notmatch '^(.+?)\s*=\s*(.+)$') { continue }
                $model = Resolve-KPStr $Matches[1]
                $ids = @($Matches[2].Split(',') | Select-Object -Skip 1 | ForEach-Object { $_.Trim().ToLower() })
                foreach ($id in $ids) { if ($want -contains $id) { return $model } }
            }
        }
    }
    return $null
}

function global:Invoke-KPWeb {

    param([string]$Uri, [string]$Method = 'Get', $Body = $null, [string]$OutFile = $null, [int]$TimeoutSec = 60)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $pp = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try {
        for ($i = 1; $i -le 3; $i++) {
            try {
                $a = @{ Uri = $Uri; Method = $Method; UseBasicParsing = $true; TimeoutSec = $TimeoutSec; ErrorAction = 'Stop' }
                if ($Body) { $a.Body = $Body; $a.ContentType = 'application/x-www-form-urlencoded' }
                if ($OutFile) { $a.OutFile = $OutFile; Invoke-WebRequest @a | Out-Null; return $true }
                return (Invoke-WebRequest @a).Content
            }
            catch { if ($i -eq 3) { throw }; Start-Sleep -Seconds (2 * $i) }
        }
    }
    finally { $ProgressPreference = $pp }
}

function global:Find-KPCatalogDriver {

    param([string[]]$HwIds, [string]$Arch, [int]$MaxTry = 6)
    $work = Join-Path $env:TEMP ("katk-prn-cat-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $work | Out-Null
    $tried = @{}
    foreach ($hw in $HwIds) {
        if (-not $hw) { continue }
        Write-Host "   Tìm trên Microsoft Update Catalog: $hw" -ForegroundColor DarkGray
        try { $html = Invoke-KPWeb -Uri ("https://www.catalog.update.microsoft.com/Search.aspx?q=" + [Uri]::EscapeDataString($hw)) }
        catch { Write-Host "   ⚠ Không vào được Catalog: $($_.Exception.Message)" -ForegroundColor Yellow; continue }
        $rows = @([regex]::Matches($html, '<a id=[''"]([0-9a-fA-F-]{36})_link[''"][^>]*>\s*([^<]+?)\s*</a>') | ForEach-Object { [pscustomobject]@{ Id = $_.Groups[1].Value; Title = [Net.WebUtility]::HtmlDecode($_.Groups[2].Value) } })

        $other = if ($Arch -eq 'arm64') { 'x64|amd64|x86' } else { 'arm64' }
        $rows = @($rows | Where-Object { $_.Title -notmatch "(?i)\b($other)\b" } | Sort-Object { if ($_.Title -match "(?i)$Arch") { 0 } else { 1 } })
        foreach ($r in $rows) {
            if ($tried.ContainsKey($r.Id) -or $tried.Count -ge $MaxTry) { continue }
            $tried[$r.Id] = 1
            try {
                $body = 'updateIDs=' + [Uri]::EscapeDataString('[{"size":0,"languages":"","uidInfo":"' + $r.Id + '","updateID":"' + $r.Id + '"}]')
                $dl = Invoke-KPWeb -Uri "https://www.catalog.update.microsoft.com/DownloadDialog.aspx" -Method Post -Body $body
                $urls = @([regex]::Matches($dl, "files\[\d+\]\.url\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
                foreach ($u in $urls) {
                    if ($u -notmatch '\.cab$') { continue }
                    $cab = Join-Path $work ([IO.Path]::GetFileName($u))
                    Write-Host "   Tải: $($r.Title)" -ForegroundColor DarkGray
                    [void](Invoke-KPWeb -Uri $u -OutFile $cab -TimeoutSec 600)
                    $dir = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($cab))
                    New-Item -ItemType Directory -Force $dir | Out-Null
                    & expand.exe $cab -F:* $dir 2>&1 | Out-Null
                    foreach ($inf in @(Get-ChildItem $dir -Recurse -Filter *.inf -ErrorAction SilentlyContinue)) {
                        $model = Get-KPInfModel -InfPath $inf.FullName -HwIds $HwIds -Arch $Arch
                        if ($model) { return @{ Dir = $dir; Inf = $inf.FullName; Model = $model; Title = $r.Title } }
                    }
                }
            } catch { Write-Host "   ⚠ Bỏ qua gói $($r.Title): $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    }
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    return $null
}

function global:Find-KPVendorDriver {

    param([string[]]$HwIds, [string]$Arch)
    if (-not $global:KP_VendorText) { return $null }
    try { $db = $global:KP_VendorText | ConvertFrom-Json } catch { return $null }
    $want = @($HwIds | Where-Object { $_ } | ForEach-Object { $_.ToUpper() -replace '^USBPRINT\\', 'U:' -replace '^LPTENUM\\', 'L:' })
    foreach ($pk in @($db.packages | Where-Object { $_.arch -eq $Arch })) {
        if (-not (@($pk.ids) | Where-Object { $want -contains $_ } | Select-Object -First 1)) { continue }
        Write-Host "   Tải driver từ hãng $($pk.vendor): $($pk.label) ($($pk.sizeMB) MB)..." -ForegroundColor Gray
        $work = Join-Path $env:TEMP ("katk-prn-ven-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            New-Item -ItemType Directory -Force $work | Out-Null
            $file = Join-Path $work ('pkg' + $(if ($pk.url -match '\.exe$') { '.exe' } else { '.zip' }))
            [void](Invoke-KPWeb -Uri $pk.url -OutFile $file -TimeoutSec 900)
            if ($pk.sha256 -and (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $pk.sha256) { throw "Tệp tải về không khớp mã SHA256" }
            $root = Join-Path $work 'x'; New-Item -ItemType Directory -Force $root | Out-Null
            & "$env:SystemRoot\System32\tar.exe" -xf $file -C $root 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Không giải nén được gói" }
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            $dir = if ($pk.sub) { Join-Path $root $pk.sub } else { $root }
            foreach ($inf in @(Get-ChildItem $dir -Filter *.inf -File -ErrorAction SilentlyContinue)) {
                $model = Get-KPInfModel -InfPath $inf.FullName -HwIds $HwIds -Arch $Arch
                if (-not $model) { continue }
                $cf = [regex]::Match([IO.File]::ReadAllText($inf.FullName), '(?im)^\s*CatalogFile[^=\r\n]*=\s*"?([^"\s;]+)').Groups[1].Value
                if (-not $cf) { throw "INF không khai báo chữ ký" }
                $sig = Get-AuthenticodeSignature -LiteralPath (Join-Path $dir $cf)
                if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike "*CN=*$($pk.signer)*") { throw "Chữ ký driver không hợp lệ" }
                if ($pk.signer -notlike 'Microsoft*') { Write-Host "   Nếu Windows hỏi có tin cậy $($pk.signer) không, bấm Install" -ForegroundColor Gray }
                return @{ Dir = $dir; Root = $work; Inf = $inf.FullName; Model = $model; Title = $pk.label }
            }
        }
        catch { Write-Host "   ⚠ $($pk.label): $($_.Exception.Message)" -ForegroundColor Yellow }
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $null
}

function global:Install-KPInfDriver {

    param([string]$Dir, [string]$Model)
    $out = & pnputil.exe /add-driver (Join-Path $Dir '*.inf') /subdirs /install 2>&1 | Out-String
    try { Add-PrinterDriver -Name $Model -ErrorAction Stop; return $true }
    catch {
        Write-Host "   ⚠ Không đăng ký được driver '$Model': $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ($out.Trim() -split "`n" | Select-Object -Last 3 | Out-String).Trim() -ForegroundColor DarkGray
        return $false
    }
}

function global:Get-KPPrinterExact([string]$Name) { Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name } | Select-Object -First 1 }
function global:Get-KPDriverExact([string]$Name) { Get-PrinterDriver -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $Name } | Select-Object -First 1 }

function global:Test-KPDriver([string]$Name) {
    return [bool](Get-KPDriverExact $Name)
}

function global:Get-KPLocalPrinters {

    @(Get-Printer -ErrorAction SilentlyContinue | Where-Object {
        $_.Type -eq 'Local' -and
        $_.Name -notlike "*$($global:KP_QueueTag)*" -and
        $_.PortName -notmatch '^(PORTPROMPT:|nul:|FILE:|XPS|SHRFAX:|KATK_)' -and
        $_.DriverName -notmatch '(?i)Print To PDF|XPS Document|OneNote|Fax' -and
        $_.Name -notmatch '(?i)^(Fax|OneNote|Microsoft Print to PDF|Microsoft XPS Document Writer)'
    } | Sort-Object Name)
}

function global:Get-KPPrinterHwIds([string]$PrinterName, [string]$DriverName) {

    $ids = @()
    try {
        foreach ($d in @(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='Printer'" -ErrorAction Stop)) {
            if ($d.Name -eq $DriverName -or $d.Name -eq $PrinterName) { $ids += @($d.HardwareID) }
        }
    } catch { }

    try { $ids = @((Get-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Control\Print\Printers\' + $PrinterName + '\PnPData') -ErrorAction Stop).HardwareID) + $ids } catch { }
    $dh = (Get-KPDriverExact $DriverName | Select-Object -First 1).HardwareID
    if ($dh -and $dh -notmatch '^\{') { $ids += $dh }
    return @($ids | Where-Object { $_ } | Select-Object -Unique)
}

function global:Get-KPDriverPackage([string]$DriverName) {

    $d = Get-KPDriverExact $DriverName | Select-Object -First 1
    if (-not $d -or -not $d.InfPath) { return @{ Inbox = $true; Dir = $null; Arch = (Get-KPArch) } }
    $dir = Split-Path -Parent $d.InfPath
    $inf = [IO.Path]::GetFileName($d.InfPath).ToLower()
    $inbox = $inf -match '^(ntprint4?|prnms\d+|prnge\d+|msprintdriver)\.inf$' -or $dir -match '\\ntprint4?\.inf_'
    $arch = if ($dir -match '_(amd64|arm64|x86)_') { $Matches[1] } else { Get-KPArch }
    return @{ Inbox = $inbox; Dir = $dir; Arch = $arch; Inf = $d.InfPath }
}

function global:Get-KPServerConfig { Read-KPJson (Join-Path $global:KP_Dir 'server.json') }

function global:Set-KPServer {

    param([string[]]$Printers)
    Initialize-KPDir
    $old = Get-KPServerConfig
    $id = if ($old -and $old.id) { $old.id } else { [Guid]::NewGuid().ToString() }

    $used = @{}; $oldPort = @{}
    if ($old) { foreach ($p in @($old.printers)) { if ($p.name -and $Printers -contains $p.name) { $oldPort[$p.name] = [int]$p.port; $used[[int]$p.port] = 1 } } }
    $drvDir = Join-Path $global:KP_Dir 'drivers'
    if (-not (Test-Path $drvDir)) { New-Item -ItemType Directory -Force $drvDir | Out-Null }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $list = @()
    foreach ($name in $Printers) {
        $q = Get-KPPrinterExact $name
        if (-not $q) { Write-Host "   ⚠ Không thấy máy in '$name'" -ForegroundColor Yellow; continue }
        if ($oldPort.ContainsKey($name)) { $port = $oldPort[$name] }
        else {
            $port = $global:KP_PortMin
            while ($used.ContainsKey($port)) { $port++ }
            if ($port -gt $global:KP_PortMax) { Write-Host "   ⚠ Hết cổng cho '$name'" -ForegroundColor Yellow; continue }
            $used[$port] = 1
        }
        $pkg = Get-KPDriverPackage $q.DriverName
        $zipName = ""
        if (-not $pkg.Inbox -and $pkg.Dir -and (Test-Path $pkg.Dir)) {
            $zipName = "drv-$port.zip"
            $zip = Join-Path $drvDir $zipName
            Write-Host "   Đóng gói driver '$($q.DriverName)' cho máy con..." -ForegroundColor DarkGray
            if (Test-Path $zip) { Remove-Item $zip -Force }
            try { [IO.Compression.ZipFile]::CreateFromDirectory($pkg.Dir, $zip) } catch { Write-Host "   ⚠ Không đóng gói được driver: $($_.Exception.Message)" -ForegroundColor Yellow; $zipName = "" }
        }
        $list += [ordered]@{
            name = $q.Name; port = $port; driver = $q.DriverName; driverArch = $pkg.Arch; inbox = [bool]$pkg.Inbox; pkg = $zipName
            hwids = @(Get-KPPrinterHwIds $q.Name $q.DriverName)
        }
    }

    foreach ($f in @(Get-ChildItem $drvDir -Filter 'drv-*.zip' -ErrorAction SilentlyContinue)) { if (-not ($list | Where-Object { $_.pkg -eq $f.Name })) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue } }
    $cfg = [ordered]@{ id = $id; name = $env:COMPUTERNAME; ctlPort = $global:KP_CtlPort; printers = @($list) }
    Write-KPJson (Join-Path $global:KP_Dir 'server.json') $cfg
    Set-KPFirewall
    Install-KPHostFiles
    Register-KPServerTask
    return $cfg
}

function global:Set-KPFirewall {
    Remove-NetFirewallRule -Group $global:KP_FwGroup -ErrorAction SilentlyContinue

    New-NetFirewallRule -DisplayName "KATK Printer - TCP" -Group $global:KP_FwGroup -Direction Inbound -Action Allow -Protocol TCP `
        -LocalPort @("$($global:KP_CtlPort)", "$($global:KP_PortMin)-$($global:KP_PortMax)") -RemoteAddress LocalSubnet -Profile Any | Out-Null
}

function global:Install-KPHostFiles {

    Initialize-KPDir
    $bom = New-Object Text.UTF8Encoding($true)
    [IO.File]::WriteAllText((Join-Path $global:KP_Dir 'PrinterCore.ps1'), $global:KP_CoreText, $bom)
    [IO.File]::WriteAllText((Join-Path $global:KP_Dir 'PrinterHost.ps1'), $global:KP_HostText, $bom)
}

function global:New-KPTaskAction([string]$Mode) {
    New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($global:KP_Dir)\PrinterHost.ps1`" -Mode $Mode"
}

function global:Register-KPServerTask {
    Stop-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $global:KP_SrvTask -ErrorAction SilentlyContinue
    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
    $p = New-ScheduledTaskPrincipal -UserId "S-1-5-18" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $global:KP_SrvTask -Action (New-KPTaskAction 'Server') -Trigger @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650))) `
        -Settings $s -Principal $p -Description "KATK Printer: nhận lệnh in từ máy con trong mạng LAN" -Force | Out-Null

    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*PrinterHost.ps1*-Mode Server*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 500
    Start-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $global:KP_SrvTask
}

function global:Test-KPServerRunning {
    try { $r = [KATKPrn.Net]::Request("127.0.0.1", $global:KP_CtlPort, '{"op":"info"}', 1500); return [bool]$r } catch { return $false }
}

function global:Remove-KPServer {
    Stop-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $global:KP_SrvTask -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like '*PrinterHost.ps1*-Mode Server*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Unregister-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $global:KP_SrvTask -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -Group $global:KP_FwGroup -ErrorAction SilentlyContinue
    foreach ($f in 'server.json', 'clients.json', 'server.log') { Remove-Item (Join-Path $global:KP_Dir $f) -Force -ErrorAction SilentlyContinue }
    Remove-Item (Join-Path $global:KP_Dir 'drivers'), (Join-Path $global:KP_Dir 'spool') -Recurse -Force -ErrorAction SilentlyContinue
}

function global:Get-KPClients {
    $c = Read-KPJson (Join-Path $global:KP_Dir 'clients.json')
    return @($c | Where-Object { $_ })
}

function global:Find-KPServers([int]$TimeoutMs = 2500) {
    $out = @()
    foreach ($line in [KATKPrn.Net]::Discover($global:KP_CtlPort, $TimeoutMs)) {
        $i = $line.IndexOf('|'); $ip = $line.Substring(0, $i)
        try { $j = $line.Substring($i + 1) | ConvertFrom-Json } catch { continue }
        $out += [pscustomobject]@{ IP = $ip; Id = $j.id; Name = $j.name; CtlPort = [int]$j.ctlPort; Printers = @($j.printers | ForEach-Object { $_.name }); Info = $j }
    }
    return @($out | Sort-Object Name)
}

function global:Get-KPServerInfo([string]$Ip, [int]$Port = $global:KP_CtlPort) {
    try { return ([KATKPrn.Net]::Request($Ip, $Port, '{"op":"info"}', 4000) | ConvertFrom-Json) } catch { return $null }
}

function global:Resolve-KPServer([string]$Text) {

    $t = $Text.Trim()
    $ip = $null
    if ($t -match '^\d{1,3}(\.\d{1,3}){3}$') { $ip = $t }
    else {
        $hit = @(Find-KPServers 2500 | Where-Object { $_.Name -ieq $t }) | Select-Object -First 1
        if ($hit) { $ip = $hit.IP }
        else { try { $ip = @([Net.Dns]::GetHostAddresses($t) | Where-Object { $_.AddressFamily -eq 'InterNetwork' })[0].ToString() } catch { } }
    }
    if (-not $ip) { return $null }
    $info = Get-KPServerInfo $ip
    if (-not $info) { return $null }
    return @{ IP = $ip; Info = $info }
}

function global:Get-KPClientConfig {
    $f = Join-Path $global:KP_Dir 'client.json'
    $c = Read-KPJson $f
    if (-not $c) { $c = [pscustomobject]@{ id = [Guid]::NewGuid().ToString(); servers = @() } }
    if (-not $c.PSObject.Properties['servers']) { $c | Add-Member servers @() }
    return $c
}

function global:Save-KPClientConfig($Cfg) { Initialize-KPDir; Write-KPJson (Join-Path $global:KP_Dir 'client.json') $Cfg }

function global:Get-KPClientIdentity($Cfg) {
    $os = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)
    $user = try { (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName } catch { "$env:USERDOMAIN\$env:USERNAME" }
    if (-not $user) { $user = "$env:USERDOMAIN\$env:USERNAME" }
    $ip = (@(Get-KPLanIPs) | Select-Object -First 1).IP
    return [ordered]@{
        id = $Cfg.id; name = $env:COMPUTERNAME; user = "$user"; arch = (Get-KPArch).ToUpper()
        os = if ($os) { "$($os.Caption) $($os.Version)" } else { "" }; code = (New-KPShortCode $Cfg.id); ip = "$ip"
    }
}

function global:Send-KPHello($Cfg, [string]$Ip, [int]$Port, [string[]]$Printers, [string]$Reason = "keep") {
    $id = Get-KPClientIdentity $Cfg
    $id['printers'] = @($Printers)
    $req = [ordered]@{ op = 'hello'; reason = $Reason; client = $id }
    try { [void][KATKPrn.Net]::Request($Ip, $Port, (ConvertTo-Json -InputObject $req -Depth 5 -Compress), 4000); return $true } catch { return $false }
}

function global:Install-KPClientDriver {

    param($P, [string]$ServerIp, [int]$CtlPort, [switch]$NoPrompt)
    $arch = Get-KPArch
    if (Test-KPDriver $P.driver) { return $P.driver }
    try { Add-PrinterDriver -Name $P.driver -ErrorAction Stop; Write-Host "   ✔ Driver có sẵn trong Windows: $($P.driver)" -ForegroundColor Green; return $P.driver } catch { }
    if ($P.pkg -and $P.driverArch -eq $arch) {
        Write-Host "   Tải driver từ máy chủ..." -ForegroundColor Gray
        $zip = Join-Path $env:TEMP ("katk-drv-" + [Guid]::NewGuid().ToString('N').Substring(0, 8) + ".zip")
        $dir = $zip -replace '\.zip$', ''
        try {
            if ([KATKPrn.Net]::Download($ServerIp, $CtlPort, ('{"op":"driver","port":' + [int]$P.port + '}'), $zip)) {
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [IO.Compression.ZipFile]::ExtractToDirectory($zip, $dir)
                if (Install-KPInfDriver -Dir $dir -Model $P.driver) { Write-Host "   ✔ Đã cài driver từ máy chủ" -ForegroundColor Green; return $P.driver }
            }
        } catch { Write-Host "   ⚠ Không tải được driver từ máy chủ: $($_.Exception.Message)" -ForegroundColor Yellow }
        finally { Remove-Item $zip, $dir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    elseif ($P.pkg) { Write-Host "   Driver của máy chủ là bản $($P.driverArch.ToUpper()), máy này cần $($arch.ToUpper()) -> tìm bản phù hợp..." -ForegroundColor Gray }
    if (@($P.hwids).Count -gt 0) {
        $hit = Find-KPCatalogDriver -HwIds @($P.hwids) -Arch $arch
        if ($hit) {
            Write-Host "   Cài driver: $($hit.Model)" -ForegroundColor Gray
            if (Install-KPInfDriver -Dir $hit.Dir -Model $hit.Model) { Remove-Item (Split-Path $hit.Dir) -Recurse -Force -ErrorAction SilentlyContinue; return $hit.Model }
        }
    }
    if (@($P.hwids).Count -gt 0) {
        $hit = Find-KPVendorDriver -HwIds @($P.hwids) -Arch $arch
        if ($hit) {
            $ok = Install-KPInfDriver -Dir $hit.Dir -Model $hit.Model
            Remove-Item $hit.Root -Recurse -Force -ErrorAction SilentlyContinue
            if ($ok) { return $hit.Model }
        }
    }
    $generic = @('Microsoft PCL6 Class Driver', 'Microsoft PS Class Driver')
    if ($NoPrompt) { return $null }
    Write-Host "   ⚠ Không tìm được driver riêng cho '$($P.driver)' ($($arch.ToUpper()))." -ForegroundColor Yellow
    Write-Host "     Có thể thử driver chung của Windows (chỉ chạy với máy in hỗ trợ PCL6 hoặc PostScript):" -ForegroundColor Gray
    Write-Host "     [1] PCL6   [2] PostScript   [0] Bỏ qua máy in này" -ForegroundColor White
    $c = Read-Host "     Chọn"
    if ($c -in '1', '2') {
        $g = $generic[[int]$c - 1]
        try { if (-not (Test-KPDriver $g)) { Add-PrinterDriver -Name $g -ErrorAction Stop }; return $g } catch { Write-Host "   ❌ Windows này không có '$g'" -ForegroundColor Red }
    }
    return $null
}

function global:Remove-KPPort([string]$Port) {

    for ($i = 0; $i -lt 8; $i++) {
        if (-not (@(Get-PrinterPort -ErrorAction SilentlyContinue) | Where-Object { $_.Name -eq $Port })) { return }
        try { Remove-PrinterPort -Name $Port -ErrorAction Stop; return } catch { Start-Sleep -Seconds 1 }
    }
}

function global:Disable-KPBidi([string]$Queue) {

    try {
        $w = Get-CimInstance Win32_Printer -ErrorAction Stop | Where-Object { $_.Name -eq $Queue } | Select-Object -First 1
        if ($w -and $w.EnableBIDI) { Set-CimInstance -InputObject $w -Property @{ EnableBIDI = $false } -ErrorAction Stop }
    } catch { }
}

function global:Wait-KPSpooler([int]$Sec = 30) {

    for ($i = 0; $i -lt $Sec; $i++) {
        if ((Get-Service Spooler).Status -eq 'Running') { try { [void]@(Get-Printer -ErrorAction Stop); return $true } catch { } }
        elseif ($i % 5 -eq 0) { Start-Service Spooler -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
    }
    return $false
}

function global:Add-KPClientPrinter {

    param([string]$ServerName, [string]$ServerIp, $P, [string]$Driver)
    $portName = "KATK_$($ServerIp)_$($P.port)"
    $queue = "$($P.name) $($global:KP_QueueTag)$ServerName)"
    if (-not (Get-PrinterPort -Name $portName -ErrorAction SilentlyContinue)) {
        Add-PrinterPort -Name $portName -PrinterHostAddress $ServerIp -PortNumber ([int]$P.port) -ErrorAction Stop
    }
    $q = Get-KPPrinterExact $queue
    if ($q) {
        $old = $q.PortName
        Set-Printer -InputObject $q -PortName $portName -DriverName $Driver -ErrorAction Stop
        if ($old -ne $portName -and $old -like 'KATK_*' -and -not (Get-Printer | Where-Object PortName -eq $old)) { Remove-KPPort $old }
    }
    else { Add-Printer -Name $queue -DriverName $Driver -PortName $portName -ErrorAction Stop }
    Disable-KPBidi $queue
    return $queue
}

function global:Invoke-KPTestPage {

    param([string]$Queue, [string]$ServerName, [string]$ServerPrinter, $Identity)
    Add-Type -AssemblyName System.Drawing
    $lines = @(
        "KATK PRINTER - TRANG IN THỬ",
        "",
        "Máy con     : $($Identity.name)",
        "Mã máy con  : $($Identity.code)",
        "IP máy con  : $($Identity.ip)",
        "Người dùng  : $($Identity.user)",
        "Windows     : $($Identity.os) ($($Identity.arch))",
        "",
        "Máy chủ     : $ServerName",
        "Máy in      : $ServerPrinter",
        "Hàng đợi    : $Queue",
        "Thời gian   : $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss'))",
        "",
        "In được trang này = máy con đã dùng được máy in qua mạng.",
        "DEV BY KATK"
    )
    $pd = New-Object System.Drawing.Printing.PrintDocument
    $pd.PrinterSettings.PrinterName = $Queue
    $pd.DocumentName = "KATK - In thu - $($Identity.name) $($Identity.code)"
    $state = @{ Lines = $lines }
    $pd.add_PrintPage({
        param($s, $e)
        $title = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
        $body = New-Object System.Drawing.Font("Consolas", 11)
        $y = [float]$e.MarginBounds.Top; $x = [float]$e.MarginBounds.Left
        $first = $true
        foreach ($l in $state.Lines) {
            $f = if ($first) { $title } else { $body }
            $e.Graphics.DrawString($l, $f, [System.Drawing.Brushes]::Black, $x, $y)
            $y += $f.GetHeight($e.Graphics) + 4
            $first = $false
        }
        $e.HasMorePages = $false
    }.GetNewClosure())
    $pd.Print()
    $pd.Dispose()
}

function global:Start-KPTestPage {

    param([string]$Queue, [string]$ServerName, [string]$ServerPrinter, $Identity)
    $name = "KATK Printer TestPage"
    $req = Join-Path $global:KP_Dir 'testpage.json'; $res = Join-Path $global:KP_Dir 'testpage.result'
    Remove-Item $res -Force -ErrorAction SilentlyContinue
    Install-KPHostFiles
    Write-KPJson $req ([ordered]@{ queue = $Queue; serverName = $ServerName; serverPrinter = $ServerPrinter; identity = $Identity })
    try {
        $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        $p = New-ScheduledTaskPrincipal -UserId "S-1-5-18" -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $name -Action (New-KPTaskAction 'TestPage') -Settings $s -Principal $p -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $name -ErrorAction Stop
        for ($i = 0; $i -lt 120 -and -not (Test-Path -LiteralPath $res); $i++) { Start-Sleep -Milliseconds 500 }
        if (-not (Test-Path -LiteralPath $res)) { throw "In thử quá 60 giây chưa xong" }
        Start-Sleep -Milliseconds 200
        $r = [IO.File]::ReadAllText($res).Trim()
        if ($r -ne 'OK') { throw $r }
    }
    finally {
        Unregister-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item $req, $res -Force -ErrorAction SilentlyContinue
    }
}

function global:Register-KPKeeperTask {

    $trig = @((New-ScheduledTaskTrigger -AtStartup), (New-ScheduledTaskTrigger -AtLogOn))
    $rep = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 3650)
    $trig += $rep
    try {
        $cls = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler
        $ev = New-CimInstance -CimClass $cls -ClientOnly
        $ev.Subscription = '<QueryList><Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational"><Select Path="Microsoft-Windows-NetworkProfile/Operational">*[System[(EventID=10000)]]</Select></Query></QueryList>'
        $ev.Enabled = $true; $ev.Delay = 'PT20S'
        $trig += $ev
    } catch { }
    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $p = New-ScheduledTaskPrincipal -UserId "S-1-5-18" -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $global:KP_KeepTask -Action (New-KPTaskAction 'Keeper') -Trigger $trig `
        -Settings $s -Principal $p -Description "KATK Printer: giữ kết nối máy in mạng (tự tìm lại máy chủ khi đổi IP)" -Force | Out-Null
}

function global:Invoke-KPKeeper {

    $cfg = Get-KPClientConfig
    $log = Join-Path $global:KP_Dir 'keeper.log'
    function KLog($m) { try { Add-Content -LiteralPath $log -Value ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + "  " + $m) -Encoding UTF8 } catch { } }
    $fixed = 0; $found = $null

    $names = $null
    for ($i = 0; $i -lt 12; $i++) {
        try { if ((Get-Service Spooler).Status -eq 'Running') { $names = @((Get-Printer -ErrorAction Stop).Name); break } } catch { }
        Start-Sleep -Seconds 5
    }
    if ($null -eq $names) { KLog "Spooler chưa chạy, bỏ qua lượt này"; return 0 }
    foreach ($s in @($cfg.servers)) {

        $s.printers = @($s.printers | Where-Object { $names -contains $_.queue })
        if (@($s.printers).Count -eq 0) { continue }
        $info = Get-KPServerInfo $s.ip ([int]$s.ctlPort)
        if (-not $info -or $info.id -ne $s.id) {
            if ($null -eq $found) { $found = @(Find-KPServers 3000) }

            $hit = $found | Where-Object { $_.Id -eq $s.id } | Select-Object -First 1
            if (-not $hit) { $hit = $found | Where-Object { $_.Name -ieq $s.name } | Select-Object -First 1 }
            if (-not $hit) { KLog "Không thấy máy chủ $($s.name) ($($s.ip))"; continue }
            if ($hit.IP -ne $s.ip) { KLog "Máy chủ $($s.name) đổi IP $($s.ip) -> $($hit.IP)" }
            $s.ip = $hit.IP; $s.id = $hit.Id; $info = $hit.Info; $fixed++
        }

        foreach ($p in @($s.printers)) {
            $rp = @($info.printers) | Where-Object { $_.name -eq $p.remote } | Select-Object -First 1
            if (-not $rp) { continue }
            $newPort = "KATK_$($s.ip)_$([int]$rp.port)"
            Disable-KPBidi $p.queue
            try {
                $q = Get-KPPrinterExact $p.queue; if (-not $q) { continue }
                $old = $q.PortName
                if ($old -ne $newPort) {
                    if (-not (Get-PrinterPort -Name $newPort -ErrorAction SilentlyContinue)) { Add-PrinterPort -Name $newPort -PrinterHostAddress $s.ip -PortNumber ([int]$rp.port) -ErrorAction Stop }
                    Set-Printer -InputObject $q -PortName $newPort -ErrorAction Stop
                    if ($old -like 'KATK_*' -and -not (Get-Printer | Where-Object PortName -eq $old)) { Remove-KPPort $old }
                }
                $p.port = [int]$rp.port
            } catch { KLog "Lỗi đổi cổng $($p.queue): $($_.Exception.Message)" }
        }
        [void](Send-KPHello $cfg $s.ip ([int]$s.ctlPort) @($s.printers | ForEach-Object { $_.remote }))
    }
    $cfg.servers = @($cfg.servers | Where-Object { @($_.printers).Count -gt 0 })
    Save-KPClientConfig $cfg
    if (@($cfg.servers).Count -eq 0) { Unregister-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $global:KP_KeepTask -Confirm:$false -ErrorAction SilentlyContinue }
    return $fixed
}

function global:Connect-KPPrinters {

    param([string]$ServerIp, $Info, $Selected, [switch]$NoPrompt, [switch]$NoTestPage)
    $cfg = Get-KPClientConfig
    $srv = @($cfg.servers) | Where-Object { $_.id -eq $Info.id } | Select-Object -First 1
    if (-not $srv) {
        $srv = [pscustomobject]@{ id = $Info.id; name = $Info.name; ip = $ServerIp; ctlPort = [int]$Info.ctlPort; printers = @() }
        $cfg.servers = @($cfg.servers) + $srv
    }
    $srv.ip = $ServerIp; $srv.name = $Info.name
    $ident = Get-KPClientIdentity $cfg
    $results = @()
    foreach ($p in @($Selected)) {
        Write-Host ""
        Write-Host "▶ $($p.name)" -ForegroundColor Cyan
        try {
            $drv = Install-KPClientDriver -P $p -ServerIp $ServerIp -CtlPort ([int]$Info.ctlPort) -NoPrompt:$NoPrompt
            if (-not $drv) { $results += [pscustomobject]@{ Printer = $p.name; Queue = $null; Ok = $false; Note = "Không có driver" }; continue }
            $queue = Add-KPClientPrinter -ServerName $Info.name -ServerIp $ServerIp -P $p -Driver $drv
            Write-Host "   ✔ Đã thêm máy in: $queue" -ForegroundColor Green

            foreach ($o in @($cfg.servers)) { if ($o -ne $srv) { $o.printers = @(@($o.printers) | Where-Object { $_.queue -ne $queue }) } }
            $srv.printers = @(@($srv.printers) | Where-Object { $_.queue -ne $queue }) + [pscustomobject]@{ queue = $queue; remote = $p.name; port = [int]$p.port }
            $results += [pscustomobject]@{ Printer = $p.name; Queue = $queue; Ok = $true; Note = $drv }
        }
        catch {
            Write-Host "   ❌ $($_.Exception.Message)" -ForegroundColor Red
            $results += [pscustomobject]@{ Printer = $p.name; Queue = $null; Ok = $false; Note = $_.Exception.Message }
        }
    }
    $cfg.servers = @($cfg.servers | Where-Object { @($_.printers).Count -gt 0 })
    Save-KPClientConfig $cfg
    if (@($cfg.servers).Count -gt 0) { Install-KPHostFiles; Register-KPKeeperTask }
    [void](Send-KPHello $cfg $ServerIp ([int]$Info.ctlPort) @($srv.printers | ForEach-Object { $_.remote }) 'connect')
    if (-not $NoTestPage) {
        foreach ($r in @($results | Where-Object Ok)) {
            try { Start-KPTestPage -Queue $r.Queue -ServerName $Info.name -ServerPrinter $r.Printer -Identity $ident; Write-Host "   🖨 Đã gửi trang in thử: $($r.Queue)" -ForegroundColor Green }
            catch { Write-Host "   ⚠ Không in thử được $($r.Queue): $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    }
    return $results
}

function global:Remove-KPClientEntry([string]$Queue) {

    $cfg = Read-KPJson (Join-Path $global:KP_Dir 'client.json')
    if (-not $cfg) { return }
    foreach ($s in @($cfg.servers)) { $s.printers = @($s.printers | Where-Object { $_.queue -ne $Queue }) }
    $cfg.servers = @($cfg.servers | Where-Object { @($_.printers).Count -gt 0 })
    Save-KPClientConfig $cfg
    if (@($cfg.servers).Count -eq 0) { Unregister-ScheduledTask -TaskPath $global:KP_TaskPath -TaskName $global:KP_KeepTask -Confirm:$false -ErrorAction SilentlyContinue }
}

function global:Get-KPAttachedPrinters {

    $out = @()
    foreach ($d in @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { @($_.HardwareID) -match '^(USBPRINT|LPTENUM)\\' })) {
        $ids = @($d.HardwareID | Where-Object { $_ })
        $name = if ($d.Name) { $d.Name } else { ($ids[0] -replace '^(USBPRINT|LPTENUM)\\', '') }
        $ok = $d.ConfigManagerErrorCode -eq 0 -and $d.PNPClass -eq 'Printer'
        $out += [pscustomobject]@{ Name = $name; DeviceId = $d.DeviceID; HwIds = $ids; HasDriver = $ok; Error = [int]$d.ConfigManagerErrorCode }
    }
    return $out
}

function global:Install-KPWindowsUpdateDriver {

    param([string[]]$HwIds)
    try {
        $sess = New-Object -ComObject Microsoft.Update.Session
        $sr = $sess.CreateUpdateSearcher()
        $sr.ServerSelection = 2
        $sr.Online = $true
        Write-Host "   Đang hỏi Windows Update (có thể mất 1-3 phút)..." -ForegroundColor DarkGray
        $res = $sr.Search("IsInstalled=0 and Type='Driver'")
        $want = @($HwIds | ForEach-Object { $_.ToLower() })
        $col = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $res.Updates) { if ($u.DriverHardwareID -and $want -contains $u.DriverHardwareID.ToLower()) { [void]$col.Add($u); Write-Host "   Thấy: $($u.Title)" -ForegroundColor Gray } }
        if ($col.Count -eq 0) { Write-Host "   Windows Update không có driver cho máy in này." -ForegroundColor DarkGray; return $false }
        $dl = $sess.CreateUpdateDownloader(); $dl.Updates = $col; [void]$dl.Download()
        $ins = $sess.CreateUpdateInstaller(); $ins.Updates = $col
        $r = $ins.Install()
        return ($r.ResultCode -eq 2 -or $r.ResultCode -eq 3)
    } catch { Write-Host "   ⚠ Windows Update lỗi: $($_.Exception.Message)" -ForegroundColor Yellow; return $false }
}

function global:Wait-KPDeviceReady($Device) {
    & pnputil.exe /scan-devices 2>&1 | Out-Null
    for ($i = 0; $i -lt 15; $i++) {
        $d = Get-CimInstance Win32_PnPEntity -Filter ("DeviceID='" + ($Device.DeviceId -replace '\\', '\\') + "'") -ErrorAction SilentlyContinue
        if ($d -and $d.ConfigManagerErrorCode -eq 0) { return $true }
        Start-Sleep 2
    }
    return $false
}

function global:Install-KPAttachedDriver {

    param($Device)
    $arch = Get-KPArch
    $loaded = $false
    foreach ($src in 'catalog', 'wu', 'vendor') {
        $ok = $false; $model = $null
        if ($src -eq 'wu') { $ok = Install-KPWindowsUpdateDriver -HwIds $Device.HwIds }
        else {
            $hit = if ($src -eq 'catalog') { Find-KPCatalogDriver -HwIds $Device.HwIds -Arch $arch } else { Find-KPVendorDriver -HwIds $Device.HwIds -Arch $arch }
            if ($hit) {
                Write-Host "   Cài: $($hit.Model) ($($hit.Title))" -ForegroundColor Gray
                $ok = Install-KPInfDriver -Dir $hit.Dir -Model $hit.Model
                $model = $hit.Model
                Remove-Item $(if ($hit.Root) { $hit.Root } else { Split-Path $hit.Dir }) -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $ok) { continue }
        $loaded = $true
        if (-not (Wait-KPDeviceReady $Device)) { continue }

        if ($model -and -not (Get-Printer -ErrorAction SilentlyContinue | Where-Object DriverName -eq $model)) {
            $port = if ("$($Device.DeviceId)" -match '((?:USB|LPT)\d+)$') { $Matches[1] } else { $null }
            if ($port -and (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue)) { try { Add-Printer -Name $model -DriverName $model -PortName $port -ErrorAction Stop } catch { } }
        }
        return $true
    }
    if ($loaded) { Write-Host "   ⚠ Đã nạp driver nhưng Windows chưa nhận máy in, thử rút cắm lại cáp" -ForegroundColor Yellow }
    return $false
}

if (-not ('KATKPrn.Carver' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
namespace KATKPrn
{
    public static class Carver
    {
        static readonly byte[][] Sig = new byte[][] {
            new byte[] { 0x4D, 0x53, 0x43, 0x46, 0, 0, 0, 0 },
            new byte[] { 0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C },
            new byte[] { 0x50, 0x4B, 0x03, 0x04 },
            new byte[] { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 },
            new byte[] { 0x52, 0x61, 0x72, 0x21, 0x1A, 0x07 } };
        static readonly string[] Ext = new string[] { ".cab", ".7z", ".zip", ".msi", ".rar" };

        public static string[] Carve(string file, string outDir, int max)
        {
            List<string> res = new List<string>();
            using (FileStream f = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20))
            {
                long len = f.Length, pos = 0, skipTo = 0;
                bool[] once = new bool[5];
                byte[] b = new byte[(1 << 20) + 64];
                int keep = 0;
                while (res.Count < max)
                {
                    f.Position = pos + keep;
                    int got = f.Read(b, keep, b.Length - keep);
                    int n = keep + got;
                    if (got <= 0) break;
                    for (int i = 0; i + 36 <= n && res.Count < max; i++)
                    {
                        long at = pos + i;
                        if (at < skipTo || at == 0) continue;
                        byte c = b[i];
                        if (c != 0x4D && c != 0x37 && c != 0x50 && c != 0xD0 && c != 0x52) continue;
                        for (int s = 0; s < Sig.Length; s++)
                        {
                            bool hit = true;
                            for (int k = 0; k < Sig[s].Length; k++) if (b[i + k] != Sig[s][k]) { hit = false; break; }
                            if (!hit || once[s]) continue;
                            long size = len - at;
                            if (s == 0)
                            {
                                long cb = BitConverter.ToUInt32(b, i + 8);
                                if (b[i + 24] != 3 || b[i + 25] != 1 || cb < 64 || cb > size) continue;
                                size = cb; skipTo = at + cb;
                            }
                            else if (s == 1) { if (b[i + 6] != 0) continue; once[s] = true; }
                            else once[s] = true;
                            string o = Path.Combine(outDir, "part" + res.Count + Ext[s]);
                            Copy(file, at, size, o);
                            res.Add(o);
                            break;
                        }
                    }
                    keep = Math.Min(35, n);
                    pos += n - keep;
                    Buffer.BlockCopy(b, n - keep, b, 0, keep);
                }
            }
            return res.ToArray();
        }

        static void Copy(string src, long at, long size, string dst)
        {
            using (FileStream i = new FileStream(src, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (FileStream o = File.Create(dst))
            {
                i.Position = at;
                byte[] b = new byte[1 << 20];
                while (size > 0) { int n = i.Read(b, 0, (int)Math.Min(b.Length, size)); if (n <= 0) break; o.Write(b, 0, n); size -= n; }
            }
        }
    }
}
'@
}

function global:Get-KPInfInfo {
    param([string]$InfPath, [string]$Arch)
    $lines = @(Get-Content -LiteralPath $InfPath -ErrorAction SilentlyContinue)
    if (-not $lines) { return $null }
    $sections = @{}; $cur = $null
    foreach ($raw in $lines) {
        $l = $raw.Trim()
        if (-not $l -or $l.StartsWith(';')) { continue }
        if ($l -match '^\[(.+?)\]') { $cur = $Matches[1].Trim().ToLower(); if (-not $sections.ContainsKey($cur)) { $sections[$cur] = New-Object System.Collections.ArrayList }; continue }
        if ($cur) { [void]$sections[$cur].Add($l) }
    }
    if (-not $sections.ContainsKey('version') -or -not $sections.ContainsKey('manufacturer')) { return $null }
    $ver = @($sections['version']) -join "`n"
    if ($ver -notmatch '(?im)^\s*Class\s*=\s*"?Printer\b' -and $ver -notmatch '(?i)4d36e979-e325-11ce-bfc1-08002be10318') { return $null }
    $cats = @([regex]::Matches($ver, '(?im)^\s*CatalogFile[^=\r\n]*=\s*"?([^"\s;]+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    $strings = @{}
    foreach ($k in @($sections.Keys | Where-Object { $_ -like 'strings*' } | Sort-Object { if ($_ -eq 'strings') { 0 } else { 1 } })) {
        foreach ($l in $sections[$k]) { if ($l -match '^([^=]+?)\s*=\s*"?(.*?)"?\s*(;.*)?$') { $n = $Matches[1].Trim().ToLower(); if (-not $strings.ContainsKey($n)) { $strings[$n] = $Matches[2] } } }
    }
    $models = New-Object System.Collections.ArrayList
    foreach ($l in $sections['manufacturer']) {
        if ($l -notmatch '=\s*([^;]+)') { continue }
        $parts = @($Matches[1].Split(',') | ForEach-Object { $_.Trim() })
        $secs = @($parts | Select-Object -Skip 1 | Where-Object { $_ -match "^nt$Arch(\.|$)" } | ForEach-Object { "$($parts[0]).$_" })
        if ($Arch -eq 'x86') { $secs += $parts[0] }
        foreach ($s in $secs) {
            $s = $s.ToLower()
            if (-not $sections.ContainsKey($s)) { continue }
            foreach ($m in $sections[$s]) {
                if ($m -notmatch '^(.+?)\s*=\s*([^;]+)') { continue }
                $name = $Matches[1].Trim().Trim('"'); $rest = $Matches[2]
                if ($name -match '^%(.+)%$') { $k = $Matches[1].ToLower(); if ($strings.ContainsKey($k)) { $name = $strings[$k] } }
                [void]$models.Add([pscustomobject]@{ Name = $name; Ids = @($rest.Split(',') | Select-Object -Skip 1 | ForEach-Object { $_.Trim().Trim('"').ToLower() } | Where-Object { $_ }) })
            }
        }
    }
    return [pscustomobject]@{ Inf = $InfPath; Dir = (Split-Path -Parent $InfPath); Cats = $cats; Models = @($models) }
}

function global:Get-KPPackageInfs([string]$Dir, [string]$Arch) {
    $out = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue | Where-Object Extension -eq '.inf')) {
        $i = Get-KPInfInfo -InfPath $f.FullName -Arch $Arch
        if ($i -and @($i.Models).Count) { $out += $i }
    }
    return $out
}

function global:Test-KPInfSigned($Info) {
    foreach ($c in @($Info.Cats)) {
        $p = Join-Path $Info.Dir $c
        if ((Test-Path -LiteralPath $p) -and (Get-AuthenticodeSignature -LiteralPath $p).Status -eq 'Valid') { return $true }
    }
    return $false
}

function global:Invoke-KPProc([string]$File, [string]$ArgLine, [int]$Sec = 600) {
    $si = New-Object Diagnostics.ProcessStartInfo $File, $ArgLine
    $si.UseShellExecute = $false; $si.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($si)
    if (-not $p.WaitForExit($Sec * 1000)) { try { $p.Kill() } catch { }; return -1 }
    return $p.ExitCode
}

function global:Expand-KPFile([string]$File, [string]$Out) {
    New-Item -ItemType Directory -Force $Out | Out-Null
    function HasOut { @(Get-ChildItem -LiteralPath $Out -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1).Count -gt 0 }
    $fs = [IO.File]::OpenRead($File); $h = New-Object byte[] 8; [void]$fs.Read($h, 0, 8); $fs.Close()
    $sig = [BitConverter]::ToString($h)
    $sys = "$env:SystemRoot\System32"
    if ($sig -like 'D0-CF-11-E0*') {
        [void](Invoke-KPProc "$sys\msiexec.exe" "/a `"$File`" /qn TARGETDIR=`"$Out`"" 900)
        Get-ChildItem -LiteralPath $Out -Filter *.msi -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        return (HasOut)
    }
    if ($sig -like '4D-53-43-46*') { [void](Invoke-KPProc "$sys\expand.exe" "-F:* `"$File`" `"$Out`""); return (HasOut) }
    $tar = "$sys\tar.exe"
    if (Test-Path $tar) { if ((Invoke-KPProc $tar "-xf `"$File`" -C `"$Out`"" 900) -eq 0 -and (HasOut)) { return $true } }
    elseif ($sig -like '50-4B-03-04*') { try { Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory($File, $Out) } catch { }; if (HasOut) { return $true } }
    foreach ($z in "$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe") {
        if (Test-Path -LiteralPath $z) { [void](Invoke-KPProc $z "x -y -o`"$Out`" `"$File`"" 900); break }
    }
    return (HasOut)
}

function global:Expand-KPPackage([string]$Path, [string]$Work, [string]$Arch) {
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue(@($Path, 0)); $count = 0
    while ($queue.Count -gt 0 -and $count -lt 60) {
        $it = $queue.Dequeue(); $file = $it[0]; $depth = [int]$it[1]; $count++
        if ((New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Work))).AvailableFreeSpace -lt 2GB) { throw "Ổ đĩa hệ thống còn dưới 2 GB, không đủ chỗ giải nén" }
        $out = Join-Path $Work "x$count"
        if ($count -le 20) { Write-Host "   Giải nén: $([IO.Path]::GetFileName($file))" -ForegroundColor DarkGray }
        $dirs = @()
        if ($file -match "[^\x20-\x7E]|[\[\]%]") {
            $ascii = Join-Path $Work ("src$count" + [IO.Path]::GetExtension($file))
            [IO.File]::Copy($file, $ascii, $true); $file = $ascii
        }
        try { if (Expand-KPFile $file $out) { $dirs += $out } } catch { }
        $infs = @(if ($dirs) { Get-KPPackageInfs $out $Arch })
        if ($infs.Count) { return $infs }
        if ([IO.Path]::GetExtension($file) -in '.exe', '.bin', '.dat') {
            $cd = Join-Path $Work "c$count"; New-Item -ItemType Directory -Force $cd | Out-Null
            try { if (@([KATKPrn.Carver]::Carve($file, $cd, 30)).Count) { $dirs += $cd } } catch { }
        }
        if ($depth -ge 3) { continue }
        foreach ($d in $dirs) {
            Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.zip', '.cab', '.msi', '.7z', '.rar', '.exe' -and ($_.Length -gt 20KB -or $_.Extension -ne '.exe') } |
                Sort-Object Length -Descending | Select-Object -First 30 | ForEach-Object { $queue.Enqueue(@($_.FullName, ($depth + 1))) }
        }
    }
    return @()
}

function global:Watch-KPVendorSetup([string]$File, [string]$Work, [string]$Arch) {
    $roots = @($env:TEMP, "$env:SystemRoot\Temp") | Select-Object -Unique
    function ListInf($r) { Get-ChildItem -LiteralPath $r -Recurse -Filter *.inf -File -ErrorAction SilentlyContinue | ForEach-Object FullName }
    function ListTop { Get-ChildItem "$env:SystemDrive\" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object FullName }
    $old = @{}; foreach ($r in $roots) { foreach ($p in @(ListInf $r)) { if ($p) { $old[$p] = 1 } } }
    $top = @(ListTop)
    $grab = Join-Path $Work 'grab'; New-Item -ItemType Directory -Force $grab | Out-Null
    $seen = @{}
    $a = @{ FilePath = $File; PassThru = $true; ErrorAction = 'Stop' }
    if ($File -match '\.msi$') { $a.FilePath = "$env:SystemRoot\System32\msiexec.exe"; $a.ArgumentList = "/i `"$File`"" }
    $proc = Start-Process @a
    $stop = $false; $idle = 0
    while (-not $stop) {
        $had = $seen.Count
        $end = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $end -and -not $stop) {
            try { if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Enter') { $stop = $true } } catch { if ($proc.HasExited) { $stop = $true } }
            Start-Sleep -Milliseconds 200
        }
        foreach ($r in @($roots) + @(ListTop | Where-Object { $top -notcontains $_ })) {
            foreach ($p in @(ListInf $r)) {
                if (-not $p -or $old.ContainsKey($p) -or $p.StartsWith($Work, [StringComparison]::OrdinalIgnoreCase)) { continue }
                $d = Split-Path -Parent $p
                if ($roots -contains $d -or $seen.ContainsKey($d)) { continue }
                if (Get-KPInfInfo -InfPath $p -Arch $Arch) { $seen[$d] = "g$($seen.Count)"; Write-Host "   Thấy driver: $([IO.Path]::GetFileName($p))" -ForegroundColor Gray }
            }
        }
        foreach ($d in @($seen.Keys)) { if (Test-Path -LiteralPath $d) { [void](Invoke-KPProc "$env:SystemRoot\System32\robocopy.exe" "`"$d`" `"$(Join-Path $grab $seen[$d])`" /E /R:0 /W:0" 120) } }
        if ($proc.HasExited -and $seen.Count -eq $had) { $idle++ } else { $idle = 0 }
        if ($idle -ge 40 -or ($idle -ge 5 -and $seen.Count -and -not @($seen.Keys | Where-Object { Test-Path -LiteralPath $_ }).Count)) { $stop = $true }
    }
    return @(Get-KPPackageInfs $grab $Arch)
}

function global:Add-KPInfToStore($Info) {
    $out = & "$env:SystemRoot\System32\pnputil.exe" /add-driver $Info.Inf /install 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($code -in 0, 259, 3010, 1641) { return $true }
    $why = @($out -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -Skip 1 | ForEach-Object { $_.Trim() } | Where-Object { $_ -notmatch ":\s+\d+$" }) -join " · "
    Write-Host "   pnputil ($code): $why" -ForegroundColor DarkGray
    return $false
}

function global:Get-KPUsbPort($Device) {
    if ("$($Device.DeviceId)" -match '((?:USB|LPT)\d+)$' -and (Get-PrinterPort -Name $Matches[1] -ErrorAction SilentlyContinue)) { return $Matches[1] }
    return $null
}

function global:Get-KPInfForDevice($Infs, $Device) {
    $want = @($Device.HwIds | ForEach-Object { "$_".ToLower() })
    foreach ($i in @($Infs)) { foreach ($m in @($i.Models)) { foreach ($id in @($m.Ids)) { if ($want -contains $id) { return [pscustomobject]@{ Info = $i; Model = $m.Name } } } } }
    return $null
}

function global:Complete-KPOfflineDevice {
    param($Device, $Infs)
    $hit = Get-KPInfForDevice $Infs $Device
    if ($hit) {
        Write-Host "   Cài: $($hit.Model)" -ForegroundColor Gray
        if (-not (Test-KPInfSigned $hit.Info)) { Write-Host "   ❌ Driver không có chữ ký hợp lệ, không cài" -ForegroundColor Red; return $false }
        if (-not (Add-KPInfToStore $hit.Info)) { Write-Host "   ❌ Windows từ chối gói driver này" -ForegroundColor Red; return $false }
        $model = $hit.Model
        [void](Wait-KPDeviceReady $Device)
    }
    else {
        $names = @($Infs | ForEach-Object { $_.Models } | ForEach-Object Name | Select-Object -Unique | Sort-Object)
        Write-Host "   Gói này không ghi mã của máy in đang cắm." -ForegroundColor Yellow
        $f = Read-Host "   Nhập tên model để chọn tay (vd: P1102), Enter = bỏ qua"
        if ([string]::IsNullOrWhiteSpace($f)) { return $false }
        $names = @($names | Where-Object { $_.IndexOf($f.Trim(), [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Select-Object -First 30)
        if ($names.Count -eq 0) { Write-Host "   Không có model nào khớp '$f'" -ForegroundColor Yellow; return $false }
        for ($i = 0; $i -lt $names.Count; $i++) { Write-Host "   [$($i + 1)] $($names[$i])" -ForegroundColor White }
        $c = Read-Host "   Chọn số, Enter = bỏ qua"
        if ($c -notmatch '^\d+$' -or [int]$c -lt 1 -or [int]$c -gt $names.Count) { return $false }
        $model = $names[[int]$c - 1]
        $info = $Infs | Where-Object { @($_.Models).Name -contains $model } | Select-Object -First 1
        if (-not (Test-KPInfSigned $info) -or -not (Add-KPInfToStore $info)) { Write-Host "   ❌ Windows từ chối gói driver này" -ForegroundColor Red; return $false }
    }
    if (-not (Test-KPDriver $model)) { try { Add-PrinterDriver -Name $model -ErrorAction Stop } catch { } }
    if (Get-Printer -ErrorAction SilentlyContinue | Where-Object DriverName -eq $model) { return $true }
    $port = Get-KPUsbPort $Device
    if (-not $port) { $port = @(Get-PrinterPort -ErrorAction SilentlyContinue | Where-Object Name -match '^USB\d+$' | ForEach-Object Name)[0] }
    if ($port) { try { Add-Printer -Name $model -DriverName $model -PortName $port -ErrorAction Stop; return $true } catch { Write-Host "   ⚠ $($_.Exception.Message)" -ForegroundColor Yellow } }
    Write-Host "   ⚠ Đã nạp driver nhưng Windows chưa nhận máy in, thử rút cắm lại cáp" -ForegroundColor Yellow
    return $false
}
