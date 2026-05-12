# Komme i gang med claudecage — for helt nybegynnere

Denne guiden er for deg som aldri har brukt Terminal og aldri har
programmert. Vi tar ett steg av gangen. Hvis noe ser skummelt ut:
det er det ikke. Du kan ikke ødelegge Macen ved å skrive feil — du
får bare en feilmelding, og prøver på nytt.

> **Hva er claudecage?** Et trygt rom (en «sandkasse») hvor du kan
> kjøre Claude Code uten at den får tilgang til hele Macen din.
> Den ser bare den mappen du sier den skal jobbe i.

---

## 1. Åpne Terminal

Terminal er et program på Macen din hvor du skriver kommandoer i
stedet for å klikke. Det er som å skrive SMS til datamaskinen.

1. Trykk `Cmd + Mellomrom` (åpner Spotlight-søk)
2. Skriv `Terminal`
3. Trykk `Enter`

Det åpner seg et vindu med tekst. Det er Terminal. Du er nå klar.

---

## 2. Tre kommandoer du må kunne

### `pwd` — «hvor er jeg?»

Skriv `pwd` og trykk Enter:

```bash
pwd
```

Du får svar som `/Users/dittnavn`. Det er mappen du står i akkurat
nå (din hjemmemappe når du nettopp åpnet Terminal).

### `ls` — «hva ligger her?»

Skriv `ls` og trykk Enter:

```bash
ls
```

Du får en liste over filer og mapper i den mappen du står i. Som å
åpne Finder, men i tekst.

### `cd` — «gå til en annen mappe»

`cd` betyr «change directory». Du skriver `cd` etterfulgt av navnet
på mappen du vil gå inn i.

```bash
cd Documents      # Går inn i Documents-mappen
cd ..             # Går ETT hakk opp (til mappen over)
cd ~              # Går tilbake til hjemmemappen din
```

**Tips:** Du slipper å skrive hele navnet — skriv noen bokstaver og
trykk `Tab`, så fyller Terminal ut resten.

**Øv litt:**

```bash
pwd            # Hvor er jeg?
ls             # Hva ligger her?
cd Documents   # Gå inn i Documents
pwd            # Sjekk at jeg flyttet meg
cd ..          # Gå tilbake
```

Det er det! Med `pwd`, `ls` og `cd` kan du navigere overalt.

---

## 3. Installer Homebrew

Homebrew er en «butikk» for utviklerverktøy på Mac. Vi trenger det
for å installere det claudecage er avhengig av.

Lim inn dette i Terminal og trykk Enter (én lang linje):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Du blir spurt om Mac-passordet ditt. Skriv det inn (du ser ingen
tegn mens du skriver — det er normalt) og trykk Enter.

Når det er ferdig, sjekk at det fungerte:

```bash
brew --version
```

Du skal få et versjonsnummer tilbake. Hvis ikke, lukk Terminal,
åpne på nytt, og prøv igjen.

---

## 4. Installer Podman og GitHub CLI

Podman kjører «containere» — små isolerte miljøer. claudecage
bruker Podman til å lage selve sandkassen.

GitHub CLI (`gh`) lar Claude snakke med GitHub for å hente og
sende kode.

```bash
brew install podman
brew install gh
```

Det tar et par minutter. Bare la det gå.

---

## 5. Start Podman-maskinen

Podman på Mac kjører i en liten virtuell maskin som må startes én
gang:

```bash
podman machine init
podman machine start
```

Du trenger bare gjøre `init` én eneste gang. `start` må gjøres på
nytt hvis du restarter Macen — eller du kan sette den til å starte
automatisk:

```bash
podman machine set --now=false  # (valgfritt)
```

Sjekk at det fungerer:

```bash
podman info
```

Hvis du får en haug med tekst tilbake — perfekt. Hvis du får feil,
prøv `podman machine start` på nytt.

---

## 6. Logg inn på GitHub

```bash
gh auth login
```

Du får spørsmål i Terminal. Svar slik:

- **What account?** → GitHub.com
- **Protocol?** → HTTPS
- **Authenticate Git?** → Yes
- **How would you like to authenticate?** → Login with a web browser

Den gir deg en kode (f.eks. `ABCD-1234`) og åpner nettleseren.
Lim inn koden i nettleseren og godkjenn.

---

## 7. Last ned claudecage

Velg hvor du vil ha den. Hjemmemappen er fin:

```bash
cd ~
gh repo clone theovald/myclaudecage
```

Nå er det en mappe som heter `myclaudecage` i hjemmemappen din.
Sjekk med `ls`.

---

## 8. Lag en snarvei (alias)

I stedet for å skrive hele stien hver gang, lager vi snarveien
`myclaude`. Lim inn:

```bash
echo 'alias myclaude="$HOME/myclaudecage/claude-container.sh"' >> ~/.zshrc
source ~/.zshrc
```

Første linje legger til snarveien. Andre linje laster den inn nå.

---

## 9. Bruk claudecage

Gå til mappen med koden du vil jobbe med. La oss si du har en
mappe `~/Documents/mitt-prosjekt`:

```bash
cd ~/Documents/mitt-prosjekt
myclaude
```

Første gang bygger den containeren. Det tar noen minutter — gå og
ta en kaffe.

Når Claude starter, får du sannsynligvis en lenke som begynner med
`claude.ai/oauth/authorize`. Kopier den lenken og lim inn i
nettleseren for å logge inn.

**Du er i gang.** Skriv hva du vil at Claude skal gjøre, så
hjelper den deg med koden i mappen du står i.

---

## Når du er ferdig

For å avslutte Claude: skriv `exit` eller trykk `Ctrl + C` to
ganger.

For å stoppe alle containere (rydde opp):

```bash
cd ~/myclaudecage
./stopAllContainers.sh
```

---

## Hvis noe går galt

- **«command not found: brew»** → Lukk Terminal, åpne på nytt.
- **«command not found: podman»** → Kjør `brew install podman`
  igjen.
- **«Cannot connect to Podman»** → Kjør `podman machine start`.
- **Containeren henger** → Kjør `./stopAllContainers.sh` fra
  `~/myclaudecage`.
- **Alt annet** → Lukk Terminal-vinduet, åpne på nytt, og prøv
  forrige steg én gang til.

---

## Ordliste

| Ord | Betyr |
| --- | --- |
| Terminal | Programmet hvor du skriver kommandoer |
| Kommando | En linje med tekst du sender til datamaskinen |
| Mappe / katalog / directory | Samme ting — som mapper i Finder |
| `~` | Snarvei for hjemmemappen din (`/Users/dittnavn`) |
| Container | Et lite isolert miljø — som en VM, men lettere |
| Sandkasse | Et trygt rom hvor programmer kjører uten å nå resten av Macen |
| Alias | En snarvei for en lang kommando |
