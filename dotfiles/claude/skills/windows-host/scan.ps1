# Read only sweep of the Windows host's services, listeners, firewall and shares.
# Runs unelevated, a few sections say so when they need --admin.

$svcs = Get-CimInstance Win32_Service

function Get-ExeCompany($path) {
	if (-not $path) { return '' }
	$exe = if ($path -match '^"([^"]+)"') { $matches[1] } else { ($path -split ' ')[0] }
	if ($exe -like '*svchost.exe') { return 'svchost' }
	if (-not (Test-Path $exe -ErrorAction SilentlyContinue)) { return 'MISSING' }
	(Get-Item $exe).VersionInfo.CompanyName
}

function Get-Owner($procId) {
	$name = (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
	$sv = ($svcs | Where-Object ProcessId -eq $procId | ForEach-Object Name) -join ','
	"pid $procId|$name|$sv"
}

"=== elevated: " + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
"=== boot: " + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

"=== services running or automatic (name|state|start|company|display)"
$svcs | Where-Object { $_.State -eq 'Running' -or $_.StartMode -eq 'Auto' } | Sort-Object Name | ForEach-Object {
	"{0}|{1}|{2}|{3}|{4}" -f $_.Name, $_.State, $_.StartMode, (Get-ExeCompany $_.PathName), $_.DisplayName
}

"=== non Microsoft services in any state (name|state|start|company|path)"
$svcs | Sort-Object Name | ForEach-Object {
	$co = Get-ExeCompany $_.PathName
	if ($co -ne 'svchost' -and $co -notlike 'Microsoft*') {
		"{0}|{1}|{2}|{3}|{4}" -f $_.Name, $_.State, $_.StartMode, $co, $_.PathName
	}
}

"=== tcp listening"
Get-NetTCPConnection -State Listen | Sort-Object LocalPort | ForEach-Object {
	"{0}:{1}|{2}" -f $_.LocalAddress, $_.LocalPort, (Get-Owner $_.OwningProcess)
}

"=== udp bound"
Get-NetUDPEndpoint | Sort-Object LocalPort | ForEach-Object {
	"{0}:{1}|{2}" -f $_.LocalAddress, $_.LocalPort, (Get-Owner $_.OwningProcess)
} | Sort-Object -Unique

"=== network profiles"
Get-NetConnectionProfile | ForEach-Object { "{0}|{1}" -f $_.InterfaceAlias, $_.NetworkCategory }

"=== netbios per adapter (0 default, 1 on, 2 off)"
Get-ChildItem HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces | ForEach-Object {
	$g = $_.PSChildName -replace 'Tcpip_', ''
	$a = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue | Where-Object InterfaceGuid -eq $g
	if ($a) { "{0}|{1}|{2}" -f $a.Name, $a.Status, (Get-ItemProperty $_.PSPath).NetbiosOptions }
}

"=== firewall profiles"
Get-NetFirewallProfile | ForEach-Object {
	"{0} enabled={1} in={2} out={3} logblocked={4} logallowed={5} log={6}" -f $_.Name, $_.Enabled, $_.DefaultInboundAction, $_.DefaultOutboundAction, $_.LogBlocked, $_.LogAllowed, $_.LogFileName
}

"=== enabled inbound allow rules (group|name|profile|program|proto/port|remote|edge)"
Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow | ForEach-Object {
	$pf = $_ | Get-NetFirewallPortFilter
	$af = $_ | Get-NetFirewallApplicationFilter
	$ad = $_ | Get-NetFirewallAddressFilter
	"{0}|{1}|{2}|{3}|{4}/{5}|{6}|{7}" -f $_.Group, $_.DisplayName, $_.Profile, $af.Program, $pf.Protocol, ($pf.LocalPort -join ' '), ($ad.RemoteAddress -join ' '), $_.EdgeTraversalPolicy
}

"=== rules pointing at programs that are gone"
Get-NetFirewallRule -Enabled True | ForEach-Object {
	$prog = ($_ | Get-NetFirewallApplicationFilter).Program
	if ($prog -and $prog -ne 'Any' -and $prog -ne 'System') {
		$p = [Environment]::ExpandEnvironmentVariables($prog)
		if (-not (Test-Path $p -ErrorAction SilentlyContinue)) { "{0}|{1}|{2}" -f $_.DisplayName, $_.Direction, $prog }
	}
}

"=== shares and smb"
"LanmanServer=" + (Get-Service LanmanServer).Status + " " + (Get-Service LanmanServer).StartType
Get-CimInstance Win32_Share -ErrorAction SilentlyContinue | ForEach-Object { "{0}|{1}" -f $_.Name, $_.Path }
try { $c = Get-SmbServerConfiguration -ErrorAction Stop; "SMB1={0} SMB2={1}" -f $c.EnableSMB1Protocol, $c.EnableSMB2Protocol } catch { "smb config needs --admin" }

"=== printers and imaging devices (these need Spooler, StiSvc and WSD discovery)"
Get-Printer -ErrorAction SilentlyContinue | ForEach-Object { "{0}|{1}" -f $_.Name, $_.PortName }
Get-PnpDevice -Class Image -PresentOnly -ErrorAction SilentlyContinue | ForEach-Object FriendlyName

"=== enabled non Microsoft scheduled tasks"
Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' } | ForEach-Object {
	"{0}{1}|{2}|{3}" -f $_.TaskPath, $_.TaskName, $_.State, (($_.Actions | ForEach-Object Execute) -join ',')
}

"=== startup entries"
Get-CimInstance Win32_StartupCommand | ForEach-Object { "{0}|{1}|{2}" -f $_.Name, $_.Location, $_.Command }

"=== defender"
try { $m = Get-MpComputerStatus -ErrorAction Stop; "realtime={0} signatures={1} lastquick={2}" -f $m.RealTimeProtectionEnabled, $m.AntivirusSignatureLastUpdated, $m.QuickScanEndTime } catch { "defender status unavailable" }

"=== remote access"
"RDP denied=" + (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server').fDenyTSConnections
Get-Service WinRM, RemoteRegistry, TermService -ErrorAction SilentlyContinue | ForEach-Object { "{0}|{1}|{2}" -f $_.Name, $_.Status, $_.StartType }
"UAC ConsentPromptBehaviorAdmin=" + (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System).ConsentPromptBehaviorAdmin
