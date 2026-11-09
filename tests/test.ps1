# Tests fuer check.ps1. Start: powershell -ExecutionPolicy Bypass -File tests\test.ps1
. (Join-Path $PSScriptRoot '..\check.ps1')
$ErrorActionPreference = 'Stop'
$script:failed = 0
function Assert-Equal($Name, $Actual, $Expected) {
    if ($Actual -eq $Expected) { Write-Host "ok    $Name" }
    else { $script:failed++; Write-Host "FEHLER $Name : ist '$Actual', soll '$Expected'" }
}

# Preise lesen
Assert-Equal 'Komma' (ConvertTo-Price '199,90 EUR') 199.9
Assert-Equal 'Punkt' (ConvertTo-Price '199.90') 199.9
Assert-Equal 'Tausender DE' (ConvertTo-Price '1.299,00') 1299
Assert-Equal 'Tausender EN' (ConvertTo-Price '1,299.00') 1299
Assert-Equal 'Nur Tausenderpunkt' (ConvertTo-Price '1.299') 1299
Assert-Equal 'Zahl' (ConvertTo-Price 219.99) 219.99
Assert-Equal 'Null' (ConvertTo-Price '0') $null
Assert-Equal 'Text' (ConvertTo-Price 'kein Preis') $null

# Seiten lesen
$ld = '<script type="application/ld+json">{"@type":"Product","offers":{"@type":"Offer","price":"219.99","availability":"https://schema.org/InStock"}}</script>'
Assert-Equal 'JSON-LD' (Get-PriceFromHtml $ld 'https://shop.example/p') 219.99
$graph = '<script type="application/ld+json">{"@graph":[{"@type":"WebPage"},{"@type":["Product"],"offers":[{"price":250},{"price":230}]}]}</script>'
Assert-Equal 'JSON-LD Graph, niedrigstes Angebot' (Get-PriceFromHtml $graph 'https://shop.example/p') 230
$agg = '<script type="application/ld+json">{"@type":"Product","offers":{"@type":"AggregateOffer","lowPrice":"150,60"}}</script>'
Assert-Equal 'JSON-LD AggregateOffer' (Get-PriceFromHtml $agg 'https://shop.example/p') 150.6
$out = '<script type="application/ld+json">{"@type":"Product","offers":{"price":"99","availability":"https://schema.org/OutOfStock"}}</script>'
Assert-Equal 'Ausverkauft zaehlt nicht' (Get-PriceFromHtml $out 'https://shop.example/p') $null
Assert-Equal 'Kaputtes JSON' (Get-PriceFromHtml '<script type="application/ld+json">{kaputt</script>' 'https://shop.example/p') $null
Assert-Equal 'Meta' (Get-PriceFromHtml '<meta property="product:price:amount" content="89.50">' 'https://shop.example/p') 89.5
Assert-Equal 'Meta umgekehrt' (Get-PriceFromHtml '<meta content="89.50" property="og:price:amount">' 'https://shop.example/p') 89.5
$amazon = '<div id="corePriceDisplay_desktop_feature_div"><span class="a-price"><span class="a-offscreen">199,90 &euro;</span></span></div>'
Assert-Equal 'Amazon' (Get-PriceFromHtml $amazon 'https://www.amazon.de/dp/X') 199.9
Assert-Equal 'Amazon ohne Angebot' (Get-PriceFromHtml '<span class="a-offscreen">5,00 EUR</span>' 'https://www.amazon.de/dp/X') $null

# Bewertung
$hist = 1..20 | ForEach-Object { [pscustomobject]@{ d = "t$_"; p = 100 + $_ } }
Assert-Equal 'Ziel erreicht' (Get-Rating 90 @([pscustomobject]@{ d = 't'; p = 90 }) 100).label 'zuschlagen'
Assert-Equal 'Zu wenig Daten' (Get-Rating 90 @([pscustomobject]@{ d = 't'; p = 90 }) $null).label 'sammeln'
Assert-Equal 'Guenstig' (Get-Rating 102 $hist $null).label 'zuschlagen'
Assert-Equal 'Mittel' (Get-Rating 108 $hist $null).label 'ok'
Assert-Equal 'Teuer' (Get-Rating 118 $hist $null).label 'warten'

# Produktliste lesen
$tmp = [IO.Path]::GetTempFileName()
[IO.File]::WriteAllText($tmp, '[{"id":"a"},{"id":"b"}]')
Assert-Equal 'Liste mit zwei Produkten' @(Read-Items $tmp).Count 2
[IO.File]::WriteAllText($tmp, '[{"id":"a"}]')
Assert-Equal 'Liste mit einem Produkt' (Read-Items $tmp)[0].id 'a'
[IO.File]::WriteAllText($tmp, '[]')
Assert-Equal 'Leere Liste' @(Read-Items $tmp).Count 0
Remove-Item $tmp

# Ablauf mit Alarm
$item = [pscustomobject]@{ id = 'a'; name = 'Test'; url = 'https://shop.example/p'; target = 100 }
$script:pushes = 0
$push = { param($i, $t, $m) $script:pushes++ }
$s = [pscustomobject]@{}
$s = Invoke-Check -Items @($item) -State ([pscustomobject]$s) -Fetch { param($i) 95.0 } -Notify $push -Today '2026-01-01'
Assert-Equal 'Erster Alarm' $script:pushes 1
Assert-Equal 'Preis gespeichert' @($s.prices['a']).Count 1
$s = $s | ConvertTo-Json -Depth 8 | ConvertFrom-Json
Assert-Equal 'Einzelner Eintrag bleibt Liste' (@($s.prices.a).Count) 1
$s = Invoke-Check -Items @($item) -State $s -Fetch { param($i) 95.0 } -Notify $push -Today '2026-01-01'
Assert-Equal 'Gleicher Tag, kein zweiter Eintrag' @($s.prices['a']).Count 1
Assert-Equal 'Gleicher Preis, kein zweiter Alarm' $script:pushes 1
$s = $s | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$s = Invoke-Check -Items @($item) -State $s -Fetch { param($i) 90.0 } -Notify $push -Today '2026-01-02'
Assert-Equal 'Tieferer Preis, neuer Alarm' $script:pushes 2
Assert-Equal 'Zwei Tage' @($s.prices['a']).Count 2
$s = $s | ConvertTo-Json -Depth 8 | ConvertFrom-Json
$s = Invoke-Check -Items @($item) -State $s -Fetch { param($i) 150.0 } -Notify $push -Today '2026-01-03'
Assert-Equal 'Preis hoch, Alarm zurueckgesetzt' $s.alerts.ContainsKey('a') $false
$s = $s | ConvertTo-Json -Depth 8 | ConvertFrom-Json
foreach ($n in 1..4) {
    $s = Invoke-Check -Items @($item) -State $s -Fetch { param($i) throw 'blockiert' } -Notify $push -Today '2026-01-04'
    $s = $s | ConvertTo-Json -Depth 8 | ConvertFrom-Json
}
Assert-Equal 'Fehler gezaehlt' ([int]$s.errors.a.count) 4
Assert-Equal 'Eine Fehlermeldung nach 4 Versuchen' $script:pushes 3
Assert-Equal 'Historie bleibt bei Fehler' @($s.prices.a).Count 3

if ($script:failed) { Write-Host "$($script:failed) Test(s) fehlgeschlagen"; exit 1 }
Write-Host 'Alle Tests bestanden'
