<#
.SYNOPSIS
    Export every slide of the parity board (docs/dashboard/index.html) as a 16:9 PNG for a slide deck.

.DESCRIPTION
    Each slide is drawn on a fixed 1280 x 720 canvas, so it fills a Google Slides page (10 x 5.625 in)
    exactly. This script opens index.html#slide=N in headless Chrome or Edge and saves slide-NN.png at
    2560 x 1440 (scale 2). In Google Slides: Insert > Image > Upload from computer, then
    Arrange > Order and size to fit the page, or crop to the area under your own title and accent line.

.PARAMETER Out
    Folder for the PNGs (made if missing). Default: timesjl-slides, beside the repository.

.PARAMETER Theme
    light (default, white slides) or dark (dark-green slides).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\dashboard_png.ps1
#>
param(
    [string]$Out = "",
    [ValidateSet("light", "dark")][string]$Theme = "light",
    [int]$Slides = 10
)
$ErrorActionPreference = "Stop"
if (-not $Out) { $Out = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "timesjl-slides" }
$page = (Resolve-Path (Join-Path $PSScriptRoot "..\docs\dashboard\index.html")).Path
$browser = @(
    "C:\Program Files\Google\Chrome\Application\chrome.exe",
    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $browser) { throw "Neither Chrome nor Edge was found." }
New-Item -ItemType Directory -Force $Out | Out-Null
$url = "file:///" + ($page -replace "\\", "/")
foreach ($n in 1..$Slides) {
    $png = Join-Path $Out ("slide-{0:D2}{1}.png" -f $n, $(if ($Theme -eq "dark") { "-dark" } else { "" }))
    # Start-Process: the browser's own log lines on stderr are not errors (Windows PowerShell 5.1 would stop on them)
    $argv = @("--headless=new", "--disable-gpu", "--hide-scrollbars", "--window-size=1280,720",
        "--force-device-scale-factor=2", "--virtual-time-budget=5000",
        "`"--screenshot=$png`"", "`"$url#slide=$n&theme=$Theme`"")
    $log = [System.IO.Path]::GetTempFileName()
    Start-Process -FilePath $browser -ArgumentList $argv -Wait -NoNewWindow -RedirectStandardError $log
    Remove-Item $log -ErrorAction SilentlyContinue
    if (-not (Test-Path $png)) { throw "slide $n was not written" }
    Write-Host "slide $n -> $png"
}
