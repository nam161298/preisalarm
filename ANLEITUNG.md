# Preisalarm einrichten

Dauer: etwa 15 Minuten. Du brauchst den PC für Schritt 1 bis 4 und das iPhone für Schritt 5 und 6.

## 1. GitHub-Projekt anlegen
1. Konto auf github.com anlegen, falls du noch keins hast.
2. Oben rechts auf **+**, dann **New repository**.
3. Name: `preisalarm`. Sichtbarkeit: **Public**, damit die kostenlose Web-App funktioniert.
4. **Create repository** antippen.

Wichtig: Bei „Public“ kann jeder deine Produktliste und Preise sehen. Trage deshalb keine privaten Daten als Produktnamen ein.

## 2. Dateien hochladen
1. Im neuen Projekt auf **uploading an existing file** klicken.
2. Den gesamten Inhalt des Ordners `Preisalarm` hineinziehen, auch den Ordner `.github`.
3. **Commit changes** klicken.
4. Prüfen, ob die Datei `.github/workflows/check.yml` im Projekt liegt. Falls nicht, Claude fragen.

## 3. Web-App einschalten
1. **Settings**, dann **Pages**.
2. Bei **Branch** `main` und `/ (root)` wählen, dann **Save**.
3. Nach ein bis zwei Minuten ist die App erreichbar unter `https://DEINNAME.github.io/preisalarm/`.

## 4. Push-Thema festlegen
1. Einen langen Namen ausdenken, den niemand errät, zum Beispiel aus vielen zufälligen Buchstaben und Zahlen. Wer ihn kennt, kann deine Meldungen lesen.
2. **Settings**, dann **Secrets and variables**, dann **Actions**, dann **New repository secret**.
3. Name: `NTFY_TOPIC`. Wert: dein ausgedachter Name.
4. Unter **Actions** die Workflows erlauben, falls GitHub danach fragt.

## 5. iPhone einrichten
1. App **ntfy** aus dem App Store laden, Mitteilungen erlauben und dein Push-Thema abonnieren.
2. Die Web-App-Adresse in **Safari** öffnen.
3. **Teilen**, dann **Zum Home-Bildschirm**.

## 6. Zugang für die App
1. Auf GitHub: **Settings** deines Kontos, **Developer settings**, **Personal access tokens**, **Fine-grained tokens**, **Generate new token**.
2. Unter **Repository access** nur `preisalarm` wählen.
3. Unter **Permissions** bei **Contents** und **Actions** jeweils **Read and write** wählen.
4. Token erzeugen und in der App auf dem Home-Bildschirm unter **Zugang** eintragen. Gib es sonst an niemanden weiter und trage es nicht in den Tresor ein.

## 7. Erster Test
1. In GitHub unter **Actions** **Preise pruefen** wählen, dann **Run workflow**.
2. Nach ein paar Minuten die App öffnen.
3. Beim Nox sollte ein Preis stehen. Liegt er bei höchstens 205 €, kommt auch eine Push-Meldung.

Danach prüft GitHub die Preise automatisch etwa alle 6 Stunden.
