param(
  [int]$Port = 5500,
  [string]$Root = '.',
  [string]$LanIp = ''
)

$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path $Root).Path

Add-Type -AssemblyName System.Web
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")

if ([string]::IsNullOrWhiteSpace($LanIp)) {
  $ipCandidate = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
      $_.IPAddress -notlike '127.*' -and
      $_.IPAddress -notlike '169.254*' -and
      $_.AddressState -eq 'Preferred'
    } |
    Select-Object -First 1

  if ($ipCandidate) {
    $LanIp = $ipCandidate.IPAddress
  }
}

if (-not [string]::IsNullOrWhiteSpace($LanIp)) {
  $listener.Prefixes.Add("http://$LanIp`:$Port/")
}

$listener.Start()

while ($listener.IsListening) {
  try {
    $context = $listener.GetContext()
    $reqPath = [System.Uri]::UnescapeDataString($context.Request.Url.AbsolutePath)
    if ($reqPath -eq '/') { $reqPath = '/index.html' }

    $safeRelative = $reqPath.TrimStart('/').Replace('/', '\\')
    $filePath = Join-Path $rootPath $safeRelative

    if ((Test-Path $filePath) -and (Get-Item $filePath).PSIsContainer) {
      $filePath = Join-Path $filePath 'index.html'
    }

    if (Test-Path $filePath -PathType Leaf) {
      $bytes = [System.IO.File]::ReadAllBytes($filePath)
      $ext = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
      $contentType = switch ($ext) {
        '.html' { 'text/html; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.gif'  { 'image/gif' }
        default { 'application/octet-stream' }
      }

      $context.Response.StatusCode = 200
      $context.Response.ContentType = $contentType
      $context.Response.ContentLength64 = $bytes.Length
      $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    else {
      $notFound = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
      $context.Response.StatusCode = 404
      $context.Response.ContentType = 'text/plain; charset=utf-8'
      $context.Response.ContentLength64 = $notFound.Length
      $context.Response.OutputStream.Write($notFound, 0, $notFound.Length)
    }

    $context.Response.OutputStream.Close()
  }
  catch {
    try { $context.Response.OutputStream.Close() } catch {}
  }
}
