# Kleiner Vorschau-Server fuer die Preisalarm-App, nur auf diesem PC erreichbar (localhost).
# Start: powershell -ExecutionPolicy Bypass -File serve.ps1 [-Port 8765] [-Root <Ordner>]
param([int]$Port = 8766, [string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
# Die Vorschau in der Claude-App gibt den Port ueber PORT vor.
if ($env:PORT) { $Port = [int]$env:PORT }

$Root = (Resolve-Path $Root).Path.TrimEnd('\')
$types = @{ '.html' = 'text/html; charset=utf-8'; '.json' = 'application/json; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'
    '.css' = 'text/css; charset=utf-8'; '.png' = 'image/png'; '.svg' = 'image/svg+xml'; '.ico' = 'image/x-icon'; '.md' = 'text/plain; charset=utf-8' }

# Speichert die Produktliste, die die App schickt (nur von dieser Seite aus, siehe Header-Pruefung).
function Save-Items($Request, $Response) {
    if ($Request.Headers['X-Preisalarm'] -ne '1') { $Response.StatusCode = 403; return 'Header fehlt' }
    if ($Request.ContentLength64 -gt 200000) { $Response.StatusCode = 413; return 'Zu gross' }
    $reader = New-Object IO.StreamReader($Request.InputStream, [Text.Encoding]::UTF8)
    $body = $reader.ReadToEnd()
    try { $parsed = $body | ConvertFrom-Json } catch { $Response.StatusCode = 400; return 'Kein JSON' }
    $list = @($parsed | ForEach-Object { $_ })
    foreach ($i in $list) {
        if (-not ($i.id -is [string]) -or -not $i.id -or -not ($i.name -is [string]) -or -not $i.name) { $Response.StatusCode = 400; return 'Produkt ohne id oder Name' }
    }
    $file = Join-Path $Root 'data\items.json'
    if (Test-Path -LiteralPath $file) { Copy-Item -LiteralPath $file (Join-Path $Root 'data\items.bak.json') -Force }
    $json = ConvertTo-Json -InputObject @($list) -Depth 6
    [IO.File]::WriteAllText($file, $json + "`n", (New-Object Text.UTF8Encoding($false)))
    return "gespeichert ($($list.Count) Produkte)"
}

$listener = New-Object Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() } catch { Write-Host "Start fehlgeschlagen: $($_.Exception.Message)"; exit 1 }
Write-Host "Preisalarm laeuft auf http://localhost:$Port/ (Ordner: $Root)"
try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $res = $ctx.Response
        try {
            $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
            if (-not $rel) { $rel = 'index.html' }
            if ($rel -eq 'api/items') {
                if ($ctx.Request.HttpMethod -ne 'POST') { $res.StatusCode = 405; Write-Host "405 /$rel"; continue }
                $msg = Save-Items $ctx.Request $res
                Write-Host "$($res.StatusCode) /$rel $msg"
                continue
            }
            $full = [IO.Path]::GetFullPath((Join-Path $Root $rel))
            $inside = $full.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)
            $hidden = $rel -match '(^|/)\.'
            if ($inside -and -not $hidden -and (Test-Path -LiteralPath $full -PathType Leaf)) {
                $bytes = [IO.File]::ReadAllBytes($full)
                $ext = [IO.Path]::GetExtension($full).ToLowerInvariant()
                $res.ContentType = $(if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' })
                $res.Headers['Cache-Control'] = 'no-store'
                $res.ContentLength64 = $bytes.Length
                if ($ctx.Request.HttpMethod -ne 'HEAD') { $res.OutputStream.Write($bytes, 0, $bytes.Length) }
                Write-Host "200 /$rel"
            } else {
                $res.StatusCode = 404
                Write-Host "404 /$rel"
            }
        } catch { $res.StatusCode = 500; Write-Host "500 $($_.Exception.Message)" }
        finally { $res.Close() }
    }
} finally { if ($listener.IsListening) { $listener.Stop() } }
