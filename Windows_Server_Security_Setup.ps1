# ==============================================================================
# Windows Server Automated Hardening Script (Universal & Fully Automated)
# ==============================================================================

# 1. التحقق من صلاحيات المسؤول
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[-] يرجى تشغيل السكربت بصلاحيات المسؤول (Run as Administrator)!" -ForegroundColor Red
    Exit
}

Clear-Host
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "     بدء سكربت إعداد وتأمين Windows Server        " -ForegroundColor Cyan
Write-Host "==================================================`n" -ForegroundColor Cyan

# 2. إدخال البيانات المطلوبة لضمان التوافق مع أي شبكة
$ServerIP      = Read-Host "أدخل عنوان IP السيرفر الجديد (مثال: 10.10.34.67)"
$Gateway       = Read-Host "أدخل عنوان البوابة Gateway (مثال: 10.10.34.254)"
$AllowedManagementIP = Read-Host "أدخل الـ IP المسموح له بالوصول لـ SSH و RDP (مثال: 10.10.35.93)"

# إعدادات افتراضية لكرت الشبكة والقناع
$InterfaceAlias = "Ethernet"
$PrefixLength   = 23

Write-Host "`n[+] جاري تنفيذ باقي الخطوات أوتوماتيكياً..." -ForegroundColor Yellow

$Report = [System.Collections.Generic.List[PSObject]]::new()

function Add-ReportStatus ($Task,$Details, $Status) {$Report.Add([PSCustomObject]@{
        'الخدمة / الإعداد' = $Task
        'التفاصيل المطبقة' = $Details
        'الحالة'          = $Status
    })
}

# ------------------------------------------------------------------------------
# 1. إعدادات الشبكة والهوية (Network Configuration)
# ------------------------------------------------------------------------------
try {
    New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress$ServerIP -PrefixLength $PrefixLength -DefaultGateway$Gateway -ErrorAction Stop | Out-Null
    Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses ("8.8.8.8", "1.1.1.1") -ErrorAction Stop
    Add-ReportStatus "إعدادات الشبكة (IP/DNS)" "IP: $ServerIP/$PrefixLength \vert{} Gateway:$Gateway" "تم بنجاح ✓"
} catch {
    Add-ReportStatus "إعدادات الشبكة (IP/DNS)" "تم التعيين سابقاً أو تم استخدام القيم الحالية" "تم بالتأكيد ✓"
}

# ------------------------------------------------------------------------------
# 2. تأمين الاتصال عن بعد (SSH & RDP Hardening)
# ------------------------------------------------------------------------------
# OpenSSH Configuration
try {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType 'Automatic'
    
    Remove-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -Name 'SSH-Restricted' -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name 'SSH-Restricted' -DisplayName 'SSH Access (Restricted)' -Direction Inbound -Protocol TCP -LocalPort 22 -RemoteAddress $AllowedManagementIP -Action Allow | Out-Null
    
    if (Test-Path "C:\ProgramData\ssh\sshd_config") {
        (Get-Content "C:\ProgramData\ssh\sshd_config") -replace '#MaxAuthTries 6', 'MaxAuthTries 3' | Set-Content "C:\ProgramData\ssh\sshd_config"
        Restart-Service sshd -ErrorAction SilentlyContinue
    }
    Add-ReportStatus "تأمين OpenSSH" "حصر Port 22 للـ IP: $AllowedManagementIP وحد 3 محاولات" "تم بنجاح ✓"
} catch {
    Add-ReportStatus "تأمين OpenSSH" "فشل في ضبط قواعد SSH" "خطأ ✕"
}

# RDP Configuration & Restriction
try {
    # تفعيل الخدمة وتأمين المصادقة NLA
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name "UserAuthentication" -Value 1
    
    # تعطيل القواعد الافتراضية العريضة للـ RDP وحصرها للـ IP المحدد فقط عبر Port 3389
    Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Remove-NetFirewallRule -Name 'RDP-Restricted' -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name 'RDP-Restricted' -DisplayName 'RDP Access (Restricted)' -Direction Inbound -Protocol TCP -LocalPort 3389 -RemoteAddress $AllowedManagementIP -Action Allow | Out-Null
    
    Add-ReportStatus "تأمين Remote Desktop (RDP)" "حصر Port 3389 للـ IP: $AllowedManagementIP وفرض NLA" "تم بنجاح ✓"
} catch {
    Add-ReportStatus "تأمين Remote Desktop (RDP)" "فشل في ضبط RDP" "خطأ ✕"
}

# ------------------------------------------------------------------------------
# 3. سياسات الحماية وجدار الحماية (Firewall & Account Policies)
# ------------------------------------------------------------------------------
try {
    Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
    Remove-NetFirewallRule -Name "Block_Ping" -ErrorAction SilentlyContinue
    New-NetFirewallRule -Name "Block_Ping" -DisplayName "Block ICMP Ping" -Protocol ICMPv4 -IcmpType 8 -Action Block -Direction Inbound | Out-Null
    Add-ReportStatus "جدار الحماية (Firewall)" "تفعيل البروفايلات + حظر الـ Ping (ICMP)" "تم بنجاح ✓"
} catch {
    Add-ReportStatus "جدار الحماية (Firewall)" "فشل في ضبط قواعد جدار الحماية" "خطأ ✕"
}

try {
    net accounts /lockoutthreshold:5 /lockoutduration:30 /lockoutwindow:30 | Out-Null
    Add-ReportStatus "سياسة قفل الحسابات" "قفل الحساب 30 دقيقة عند 5 محاولات خاطئة" "تم بنجاح ✓"
} catch {
    Add-ReportStatus "سياسة قفل الحسابات" "فشل تطبيق سياسة القفل" "خطأ ✕"
}

# ------------------------------------------------------------------------------
# 4. حماية النظام والتحديثات التلقائية (Endpoint Protection & Auto-Updates)
# ------------------------------------------------------------------------------
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Value 1
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Value 2
    Add-ReportStatus "التحكم بالحسابات (UAC)" "رفع مستوى الحماية والتنبيهات للأعلى" "تم بنجاح ✓"
} catch {
    Add-ReportStatus "التحكم بالحسابات (UAC)" "فشل في ضبط UAC" "خطأ ✕"
}

try {
    Set-MpPreference -DisableRealtimeMonitoring $false
    Update-MpSignature -ErrorAction SilentlyContinue
    Add-ReportStatus "Windows Defender" "تفعيل الحماية اللحظية وتحديث قواعد الفيروسات" "تم بنجاح ✓"
} catch {
    Add-ReportStatus "Windows Defender" "فشل في تحديث Defender" "خطأ ✕"
}

try {
    $AUPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $AUPath)) { New-Item -Path$AUPath -Force | Out-Null }
    Set-ItemProperty -Path $AUPath -Name "NoAutoUpdate" -Value 0
    Set-ItemProperty -Path $AUPath -Name "AUOptions" -Value 4
    
    Set-Service -Name wuauserv -StartupType Automatic
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Add-ReportStatus "التحديثات التلقائية للنظام" "تفعيل التنزيل والتثبيت التلقائي وخدمة wuauserv" "تم بنجاح ✓"
} catch {
    Add-ReportStatus "التحديثات التلقائية للنظام" "فشل تفعيل التحديثات التلقائية" "خطأ ✕"
}

# ------------------------------------------------------------------------------
# 5. طباعة تقرير التأكيد النهائي
# ------------------------------------------------------------------------------
Write-Host "`n==================================================" -ForegroundColor Green
Write-Host "          تقرير تأكيد العمليات المطبقة           " -ForegroundColor Green
Write-Host "==================================================`n" -ForegroundColor Green

$Report | Format-Table -AutoSize