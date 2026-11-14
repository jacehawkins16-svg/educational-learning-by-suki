param()
$ErrorActionPreference = 'Stop'

$root = [System.IO.Path]::GetFullPath($PSScriptRoot)
$configPath = Join-Path $root 'site-index.txt'
$indexFile = 'index.html'
if (Test-Path -LiteralPath $configPath) {
    $configured = (Get-Content -LiteralPath $configPath -Raw -ErrorAction Stop).Trim()
    if (-not [string]::IsNullOrWhiteSpace($configured)) { $indexFile = $configured }
}
$indexPath = [System.IO.Path]::GetFullPath((Join-Path $root $indexFile))
$rootPrefix = $root.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)) + [System.IO.Path]::DirectorySeparatorChar
if (-not $indexPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
    throw "The local start page was not found inside this folder: $indexPath"
}

function Get-MimeType([string]$Path) {
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { 'text/html; charset=utf-8'; break }
        '.htm' { 'text/html; charset=utf-8'; break }
        '.css' { 'text/css; charset=utf-8'; break }
        '.js' { 'application/javascript; charset=utf-8'; break }
        '.mjs' { 'application/javascript; charset=utf-8'; break }
        '.json' { 'application/json; charset=utf-8'; break }
        '.webmanifest' { 'application/manifest+json; charset=utf-8'; break }
        '.svg' { 'image/svg+xml'; break }
        '.png' { 'image/png'; break }
        '.jpg' { 'image/jpeg'; break }
        '.jpeg' { 'image/jpeg'; break }
        '.gif' { 'image/gif'; break }
        '.webp' { 'image/webp'; break }
        '.avif' { 'image/avif'; break }
        '.ico' { 'image/x-icon'; break }
        '.woff' { 'font/woff'; break }
        '.woff2' { 'font/woff2'; break }
        '.ttf' { 'font/ttf'; break }
        '.otf' { 'font/otf'; break }
        '.mp3' { 'audio/mpeg'; break }
        '.wav' { 'audio/wav'; break }
        '.ogg' { 'audio/ogg'; break }
        '.mp4' { 'video/mp4'; break }
        '.webm' { 'video/webm'; break }
        '.wasm' { 'application/wasm'; break }
        '.xml' { 'application/xml; charset=utf-8'; break }
        '.txt' { 'text/plain; charset=utf-8'; break }
        default { 'application/octet-stream' }
    }
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$url = "http://127.0.0.1:$port/"
Write-Host ''
Write-Host 'DeltaMath local-site workaround' -ForegroundColor Cyan
Write-Host "Serving folder: $root" -ForegroundColor Gray
Write-Host "Opening: $url" -ForegroundColor Green
Write-Host 'Keep this window open while using the local copy. Press Ctrl+C to stop.' -ForegroundColor Yellow
Write-Host ''
try {
    Start-Process -FilePath $url
} catch {
    Write-Host "Open this address manually: $url" -ForegroundColor Yellow
}

try {
    while ($true) {
        $client = $null
        $reader = $null
        try {
            $client = $listener.AcceptTcpClient()
            $client.NoDelay = $true
            $client.ReceiveTimeout = 8000
            $stream = $client.GetStream()
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) { continue }
            $parts = $requestLine.Split(' ')
            if ($parts.Length -lt 2) { continue }
            $method = $parts[0].ToUpperInvariant()
            $target = $parts[1]
            while ($true) {
                $headerLine = $reader.ReadLine()
                if ($null -eq $headerLine -or $headerLine.Length -eq 0) { break }
            }

            $status = '200 OK'
            $body = [byte[]]@()
            $mime = 'text/plain; charset=utf-8'
            if ($method -notin @('GET', 'HEAD')) {
                $status = '405 Method Not Allowed'
                $body = [System.Text.Encoding]::UTF8.GetBytes('Method not allowed')
            }
            else {
                try {
                    if ($target -match '^https?://') { $requestUri = [System.Uri]::new($target) }
                    else { $requestUri = [System.Uri]::new("http://127.0.0.1:$port$target") }
                    $relative = [System.Uri]::UnescapeDataString($requestUri.AbsolutePath.TrimStart('/'))
                    if ([string]::IsNullOrWhiteSpace($relative)) { $relative = $indexFile }
                    $candidate = [System.IO.Path]::GetFullPath((Join-Path $root ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)))
                    if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $status = '403 Forbidden'
                        $body = [System.Text.Encoding]::UTF8.GetBytes('Forbidden')
                    }
                    else {
                        if ((Test-Path -LiteralPath $candidate -PathType Container)) {
                            $candidate = Join-Path $candidate 'index.html'
                        }
                        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                            # Gatsby-style client routes have no file extension; serve the local entry page.
                            if ([string]::IsNullOrEmpty([System.IO.Path]::GetExtension($candidate))) {
                                $candidate = $indexPath
                            }
                        }
                        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                            $body = [System.IO.File]::ReadAllBytes($candidate)
                            $mime = Get-MimeType $candidate
                        }
                        else {
                            $status = '404 Not Found'
                            $body = [System.Text.Encoding]::UTF8.GetBytes('File not found')
                        }
                    }
                } catch {
                    $status = '400 Bad Request'
                    $body = [System.Text.Encoding]::UTF8.GetBytes('Bad request')
                }
            }
            $header = "HTTP/1.1 $status`r`nContent-Type: $mime`r`nContent-Length: $($body.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`nX-Content-Type-Options: nosniff`r`n`r`n"
            $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
            $stream.Write($headerBytes, 0, $headerBytes.Length)
            if ($method -ne 'HEAD' -and $body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
            $stream.Flush()
        } catch {
            # Ignore an individual browser request failure and keep the local server alive.
        } finally {
            if ($reader) { $reader.Dispose() }
            if ($client) { $client.Close() }
        }
    }
} finally {
    $listener.Stop()
}