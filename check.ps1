# Preisalarm: prueft alle Produkte, speichert die Preise, bewertet sie und meldet gute Preise.
# Laeuft mit Windows PowerShell 5.1 und mit pwsh in der Cloud.
param([string]$DataDir = (Join-Path $PSScriptRoot 'data'))

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:MinDays = 14

function ConvertTo-Price($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [ValueType]) {
        $n = [double]$Value
        if ($n -gt 0) { return [math]::Round($n, 2) }
        return $null
    }
    $s = ([string]$Value) -replace '[^\d.,]', ''
    $s = $s.Trim('.', ',')
    if (-not $s) { return $null }
    $c = $s.LastIndexOf(',')
    $d = $s.LastIndexOf('.')
    if ($c -ge 0 -and $d -ge 0) {
        if ($c -gt $d) { $s = $s.Replace('.', '').Replace(',', '.') }
        else { $s = $s.Replace(',', '') }
    }
    elseif ($c -ge 0) {
        if ($s -match ',\d{1,2}$') { $s = $s.Replace(',', '.') } else { $s = $s.Replace(',', '') }
    }
    elseif ($d -ge 0) {
        if ($s -match '\.\d{3}$') { $s = $s.Replace('.', '') }
    }
    $n = 0.0
    $ok = [double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)
    if ($ok -and $n -gt 0) { return [math]::Round($n, 2) }
    return $null
}

function Get-OfferPrices($Offers) {
    foreach ($o in @($Offers)) {
        if ($null -eq $o) { continue }
        if ([string]$o.availability -match 'OutOfStock|SoldOut|Discontinued') { continue }
        if ($o.offers) { Get-OfferPrices $o.offers; continue }
        $value = $o.lowPrice
        if ($null -eq $value) { $value = $o.price }
        if ($null -eq $value -and $o.priceSpecification) { $value = @($o.priceSpecification)[0].price }
        $p = ConvertTo-Price $value
        if ($p) { $p }
    }
}

function Find-LdPrice($Node) {
    if ($null -eq $Node -or $Node -is [string] -or $Node -is [ValueType]) { return $null }
    if ($Node -is [array]) {
        foreach ($n in $Node) {
            $p = Find-LdPrice $n
            if ($p) { return $p }
        }
        return $null
    }
    if (@($Node.'@type') -contains 'Product') {
        $prices = @(Get-OfferPrices $Node.offers)
        if ($prices.Count) { return ($prices | Measure-Object -Minimum).Minimum }
    }
    if ($Node.'@graph') { return Find-LdPrice @($Node.'@graph') }
    return $null
}

function Get-PriceFromHtml([string]$Html, [string]$Url) {
    if ($Url -match '://[^/]*amazon\.') {
        $m = [regex]::Match($Html, '(?is)(?:id="corePriceDisplay_desktop_feature_div"|id="corePrice_feature_div"|id="corePrice_desktop"|priceToPay).{0,3000}?class="a-offscreen">\s*([^<]+?)\s*<')
        if ($m.Success) { return ConvertTo-Price $m.Groups[1].Value }
        return $null
    }
    foreach ($m in [regex]::Matches($Html, '(?is)<script[^>]+application/ld\+json[^>]*>(.*?)</script>')) {
        try { $json = $m.Groups[1].Value | ConvertFrom-Json } catch { continue }
        $p = Find-LdPrice $json
        if ($p) { return $p }
    }
    $patterns = @(
        '(?is)<meta[^>]+(?:property|name|itemprop)=["''](?:product:price:amount|og:price:amount|price)["''][^>]*content=["'']([^"'']+)',
        '(?is)<meta[^>]+content=["'']([^"'']+)["''][^>]*(?:property|name|itemprop)=["''](?:product:price:amount|og:price:amount|price)["'']',
        '(?is)itemprop=["'']price["''][^>]*content=["'']([^"'']+)'
    )
    foreach ($pattern in $patterns) {
        $m = [regex]::Match($Html, $pattern)
        if ($m.Success) {
            $p = ConvertTo-Price $m.Groups[1].Value
            if ($p) { return $p }
        }
    }
    return $null
}

function Get-Rating([double]$Price, $History, $Target) {
    $all = @($History | ForEach-Object { [double]$_.p } | Sort-Object)
    $days = $all.Count
    $low = $all[0]
    $median = $all[[math]::Floor(0.5 * ($days - 1))]
    $p20 = $all[[math]::Floor(0.2 * ($days - 1))]
    $result = [ordered]@{ label = 'sammeln'; reason = ''; low = $low; median = $median; days = $days }
    if ($null -ne $Target -and [double]$Target -gt 0 -and $Price -le [double]$Target) {
        $result.label = 'zuschlagen'
        $result.reason = 'Zielpreis erreicht'
    }
    elseif ($days -lt $script:MinDays) {
        $result.reason = "Noch zu wenig eigene Daten ($days von $($script:MinDays) Tagen)"
    }
    elseif ($Price -le $p20) {
        $result.label = 'zuschlagen'
        $result.reason = 'Preis liegt im untersten Bereich der eigenen Daten'
    }
    elseif ($Price -le $median) {
        $result.label = 'ok'
        $result.reason = 'Preis liegt unter dem mittleren Preis'
    }
    else {
        $result.label = 'warten'
        $result.reason = 'Preis liegt oberhalb des mittleren Preises'
    }
    return $result
}

function ConvertTo-Map($Object) {
    $map = @{}
    if ($null -ne $Object) {
        foreach ($prop in $Object.PSObject.Properties) { $map[$prop.Name] = $prop.Value }
    }
    return $map
}

function Invoke-Check {
    param($Items, $State, [scriptblock]$Fetch, [scriptblock]$Notify, [string]$Today)
    $prices = ConvertTo-Map $State.prices
    $alerts = ConvertTo-Map $State.alerts
    $errors = ConvertTo-Map $State.errors
    $ratings = ConvertTo-Map $State.ratings

    foreach ($item in @($Items)) {
        $id = [string]$item.id
        $price = $null
        $message = 'Preis nicht gefunden oder Seite blockiert'
        try { $price = & $Fetch $item } catch { $message = $_.Exception.Message }

        if (-not $price) {
            $count = 1
            if ($errors.ContainsKey($id)) { $count = [int]$errors[$id].count + 1 }
            $errors[$id] = [ordered]@{ count = $count; message = $message; date = $Today }
            if ($count -eq 4) {
                try { & $Notify $item 'Preis nicht lesbar' "$($item.name): $message" } catch { Write-Warning $_.Exception.Message }
            }
            Write-Host "FEHLER $($item.name): $message"
            continue
        }

        [void]$errors.Remove($id)
        $list = @()
        if ($prices.ContainsKey($id)) { $list = @($prices[$id]) }
        $entry = [pscustomobject]@{ d = $Today; p = $price }
        if ($list.Count -and $list[-1].d -eq $Today) { $list[-1] = $entry } else { $list += $entry }
        $prices[$id] = @($list)

        $rating = Get-Rating $price $list $item.target
        $ratings[$id] = $rating
        Write-Host "OK $($item.name): $price EUR, $($rating.label)"

        if ($rating.label -eq 'zuschlagen') {
            if (-not $alerts.ContainsKey($id) -or $price -lt [double]$alerts[$id]) {
                try {
                    & $Notify $item "Guter Preis: $price EUR" "$($item.name): $($rating.reason)"
                    $alerts[$id] = $price
                } catch { Write-Warning $_.Exception.Message }
            }
        }
        else { [void]$alerts.Remove($id) }
    }
    return [ordered]@{ prices = $prices; alerts = $alerts; errors = $errors; ratings = $ratings; updated = $Today }
}

function Get-ItemPrice($Item) {
    $headers = @{ 'User-Agent' = 'Mozilla/5.0 (compatible; Preisalarm/1.0)'; 'Accept-Language' = 'de-DE,de;q=0.9' }
    $response = Invoke-WebRequest -Uri $Item.url -Headers $headers -UseBasicParsing -TimeoutSec 30
    return Get-PriceFromHtml ([string]$response.Content) ([string]$Item.url)
}

function Send-Push($Item, [string]$Title, [string]$Message) {
    $topic = $env:NTFY_TOPIC
    if (-not $topic) { Write-Host "OHNE PUSH: $Title - $Message"; return }
    $body = @{ topic = $topic; title = $Title; message = $Message; click = [string]$Item.url; priority = 4; tags = @('moneybag') } | ConvertTo-Json
    $bytes = [Text.Encoding]::UTF8.GetBytes($body)
    [void](Invoke-RestMethod -Uri 'https://ntfy.sh/' -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 30)
}

function Read-Json([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Read-Items([string]$Path) {
    # Windows PowerShell liefert eine JSON-Liste als ein Objekt, die Pipeline loest sie auf.
    return @(Read-Json $Path | ForEach-Object { $_ })
}

if ($MyInvocation.InvocationName -ne '.') {
    $items = Read-Items (Join-Path $DataDir 'items.json')
    $state = Read-Json (Join-Path $DataDir 'history.json')
    $today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $fetch = { param($i) Get-ItemPrice $i }
    $notify = { param($i, $t, $m) Send-Push $i $t $m }
    $newState = Invoke-Check -Items $items -State $state -Fetch $fetch -Notify $notify -Today $today
    $json = $newState | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText((Join-Path $DataDir 'history.json'), $json, (New-Object Text.UTF8Encoding($false)))
}
