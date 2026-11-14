# Preisalarm-Prototyp: liest die Funde der Preissuche (data/funde/*.json),
# speichert den besten sicheren Preis in der Historie, bewertet ihn und schreibt die Angebotsliste fuer die App.
# Start: powershell -ExecutionPolicy Bypass -File update.ps1   (optional: -Funde <Datei>)
param([string]$DataDir = (Join-Path $PSScriptRoot 'data'), [string]$Funde = '')

# check.ps1 hat einen eigenen DataDir-Parameter, der beim Einbinden unseren ueberschreiben wuerde.
$keepDataDir = $DataDir
. (Join-Path $PSScriptRoot 'check.ps1')
$DataDir = $keepDataDir
$ErrorActionPreference = 'Stop'

function Get-OfferTotal($Offer) {
    $p = ConvertTo-Price $Offer.preis
    if (-not $p) { return $null }
    $v = 0.0
    if ($null -ne $Offer.versand) { $v = [double]$Offer.versand }
    return [math]::Round($p + $v, 2)
}

function Test-TitleMatch($Item, [string]$Title) {
    $t = $Title.ToLowerInvariant()
    foreach ($w in @($Item.muss)) { if ($w -and -not $t.Contains(([string]$w).ToLowerInvariant())) { return $false } }
    foreach ($w in @($Item.nicht)) { if ($w -and $t.Contains(([string]$w).ToLowerInvariant())) { return $false } }
    return $true
}

function Test-Countable($Item, $Offer) {
    return ($Offer.zustand -eq 'neu' -and $Offer.vertrauen -eq 'bekannt' -and $Offer.quelle -eq 'geprueft' -and
        (Test-TitleMatch $Item ([string]$Offer.titel)) -and $null -ne (Get-OfferTotal $Offer))
}

function Get-OfferList($Item, $Offers) {
    $list = foreach ($o in @($Offers)) {
        if ($null -eq $o) { continue }
        $total = Get-OfferTotal $o
        if ($null -eq $total) { continue }
        [ordered]@{
            shop = [string]$o.shop; url = [string]$o.url; titel = [string]$o.titel
            preis = ConvertTo-Price $o.preis; versand = $o.versand; gesamt = $total
            zustand = [string]$o.zustand; land = [string]$o.land; quelle = [string]$o.quelle
            vertrauen = [string]$o.vertrauen; hinweis = [string]$o.hinweis
            zaehlt = [bool](Test-Countable $Item $o); modell = [bool](Test-TitleMatch $Item ([string]$o.titel))
        }
    }
    return @($list | Sort-Object { -not $_.zaehlt }, { $_.gesamt })
}

function Get-BestOffer($List) {
    return @($List | Where-Object { $_.zaehlt } | Sort-Object { $_.gesamt }) | Select-Object -First 1
}

function Invoke-Update {
    param($Items, $State, $Found, [scriptblock]$Notify)
    $offers = @{}
    foreach ($item in @($Items)) {
        $id = [string]$item.id
        $raw = $null
        if ($Found.produkte -and $Found.produkte.$id) { $raw = $Found.produkte.$id.angebote }
        $list = Get-OfferList $item $raw
        $offers[$id] = [ordered]@{ datum = [string]$Found.datum; bestes = (Get-BestOffer $list); angebote = $list }
    }
    $fetch = {
        param($i)
        $best = $offers[[string]$i.id].bestes
        if (-not $best) { throw 'Kein geprueftes Angebot gefunden' }
        return [double]$best.gesamt
    }.GetNewClosure()
    $newState = Invoke-Check -Items $Items -State $State -Fetch $fetch -Notify $Notify -Today ([string]$Found.datum)
    return [ordered]@{ state = $newState; offers = [ordered]@{ updated = [string]$Found.datum; items = $offers } }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Funde) {
        $Funde = Get-ChildItem (Join-Path $DataDir 'funde') -Filter '*.json' | Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
    }
    if (-not $Funde) { throw 'Keine Funde gefunden (data/funde/*.json)' }
    Write-Host "Funde: $Funde"
    $items = Read-Items (Join-Path $DataDir 'items.json')
    $state = Read-Json (Join-Path $DataDir 'history.json')
    $found = Read-Json $Funde
    $notify = { param($i, $t, $m) Send-Push $i $t $m }
    $result = Invoke-Update -Items $items -State $state -Found $found -Notify $notify
    $utf8 = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText((Join-Path $DataDir 'history.json'), ($result.state | ConvertTo-Json -Depth 8), $utf8)
    [IO.File]::WriteAllText((Join-Path $DataDir 'offers.json'), ($result.offers | ConvertTo-Json -Depth 8), $utf8)
    foreach ($id in $result.offers.items.Keys) {
        $b = $result.offers.items[$id].bestes
        if ($b) { Write-Host "BESTES $id`: $($b.gesamt) EUR bei $($b.shop)" }
    }
}
