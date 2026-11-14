# Tests fuer update.ps1. Start: powershell -ExecutionPolicy Bypass -File tests\test-update.ps1
. (Join-Path $PSScriptRoot '..\update.ps1')
$ErrorActionPreference = 'Stop'
$script:failed = 0
function Assert-Equal($Name, $Actual, $Expected) {
    if ($Actual -eq $Expected) { Write-Host "ok    $Name" }
    else { $script:failed++; Write-Host "FEHLER $Name : ist '$Actual', soll '$Expected'" }
}

$item = [pscustomobject]@{ id = 'n'; name = 'Nox'; target = 205; muss = @('at10', 'genius'); nicht = @('attack', 'lite') }
function New-Offer($Titel, $Preis, $Versand = $null, $Zustand = 'neu', $Quelle = 'geprueft', $Vertrauen = 'bekannt') {
    [pscustomobject]@{ shop = 'S'; url = 'https://s.example/p'; titel = $Titel; preis = $Preis; versand = $Versand
        zustand = $Zustand; land = 'DE'; quelle = $Quelle; vertrauen = $Vertrauen; hinweis = '' }
}

# Modell erkennen
Assert-Equal 'Richtiges Modell' (Test-TitleMatch $item 'NOX AT10 Genius 12K') $true
Assert-Equal 'Attack ausgeschlossen' (Test-TitleMatch $item 'Nox AT10 Genius Attack 12K') $false
Assert-Equal 'Pflichtwort fehlt' (Test-TitleMatch $item 'Nox ML10 12K') $false

# Gesamtpreis
Assert-Equal 'Mit Versand' (Get-OfferTotal (New-Offer 'x' 150 7.69)) 157.69
Assert-Equal 'Ohne Versandangabe' (Get-OfferTotal (New-Offer 'x' '224,95')) 224.95

# Was zaehlt
$offers = @(
    (New-Offer 'Nox AT10 Genius Attack' 179.95),
    (New-Offer 'Nox AT10 Genius 12K' 229.95),
    (New-Offer 'Nox AT10 Genius 12K' 224.95),
    (New-Offer 'Nox AT10 Genius 12K' 150 7.69 'unbekannt' 'suchtreffer' 'unbekannt'),
    (New-Offer 'Nox AT10 Genius 12K' 199 $null 'neu' 'suchtreffer' 'bekannt'),
    (New-Offer 'Nox AT10 Genius 12K' 120 $null 'neu' 'geprueft' 'verdacht')
)
$list = Get-OfferList $item $offers
Assert-Equal 'Alle Angebote in der Liste' $list.Count 6
Assert-Equal 'Zwei zaehlen' @($list | Where-Object { $_.zaehlt }).Count 2
$best = Get-BestOffer $list
Assert-Equal 'Bestes sicheres Angebot' $best.gesamt 224.95
Assert-Equal 'Zaehlende stehen oben' $list[0].gesamt 224.95
Assert-Equal 'Falsches Modell markiert' (@($list | Where-Object { $_.gesamt -eq 179.95 })[0].modell) $false

# Ablauf
$script:pushes = 0
$push = { param($i, $t, $m) $script:pushes++ }
$found = [pscustomobject]@{ datum = '2026-11-11'; produkte = [pscustomobject]@{ n = [pscustomobject]@{ angebote = $offers } } }
$r = Invoke-Update -Items @($item) -State ([pscustomobject]@{}) -Found $found -Notify $push
Assert-Equal 'Historie mit bestem Preis' @($r.state.prices['n'])[0].p 224.95
Assert-Equal 'Kein Alarm ueber Zielpreis' $script:pushes 0
Assert-Equal 'Angebotsliste gespeichert' @($r.offers.items['n'].angebote).Count 6

$cheap = @((New-Offer 'Nox AT10 Genius 12K' 199.9))
$found2 = [pscustomobject]@{ datum = '2026-11-12'; produkte = [pscustomobject]@{ n = [pscustomobject]@{ angebote = $cheap } } }
$state = $r.state | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$r2 = Invoke-Update -Items @($item) -State $state -Found $found2 -Notify $push
Assert-Equal 'Alarm bei Zielpreis' $script:pushes 1
Assert-Equal 'Zwei Tage Historie' @($r2.state.prices['n']).Count 2

$found3 = [pscustomobject]@{ datum = '2026-11-13'; produkte = [pscustomobject]@{} }
$state = $r2.state | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$r3 = Invoke-Update -Items @($item) -State $state -Found $found3 -Notify $push
Assert-Equal 'Ohne Fund: Fehler gezaehlt' ([int]$r3.state.errors['n'].count) 1
Assert-Equal 'Ohne Fund: Historie bleibt' @($r3.state.prices['n']).Count 2
Assert-Equal 'Ohne Fund: kein bestes Angebot' $r3.offers.items['n'].bestes $null

if ($script:failed) { Write-Host "$($script:failed) Test(s) fehlgeschlagen"; exit 1 }
Write-Host 'Alle Tests bestanden'
