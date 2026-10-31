# Scachs: TestFlight i App Store Connect

## Ja fet
- `Scachs/App/PrivacyInfo.xcprivacy`: sense seguiment ni dades recollides. `UserDefaults` declarat (CA92.1). El binari no importa cap API de temps de fitxer.
- `ITSAppUsesNonExemptEncryption = NO`: només s'usa l'HTTPS del sistema.
- Icona de 1024 px sense alfa, amb variants fosca i tenyida.
- Textos de la fitxa en tres idiomes a `metadata.md`. Política de privacitat a `privacy.md`.
- Bundle `com.jsolee.scachs`, equip `MUY564KAW3`, iOS 26+, només iPhone.
- `scripts/testflight.sh`: arxiva en Release i puja. El número de build és la data i l'hora.

## T'ho cal fer a tu
1. **Crear l'app a App Store Connect** (Apps > + > Nova app): plataforma iOS, nom «Scachs: Chess Puzzles & Review», idioma principal català, bundle `com.jsolee.scachs`, SKU `scachs`. El bundle s'hauria de registrar sol amb el primer arxivat; si no surt a la llista, executa abans `scripts/testflight.sh --no-upload`.
2. **Pujar:** `scripts/testflight.sh`. Signa amb el compte de Xcode (Ajustes > Comptes), el mateix de Niwa.
3. **Grup intern:** crea'l a TestFlight («Scachs intern») amb distribució automàtica i afegeix-t'hi.
4. **Abans de provadors externs (GPL):**
   - Puja el codi: el repo ha de ser públic amb l'etiqueta exacta de la build. Substitueix `[URL DEL REPO]` a `metadata.md`.
   - Consulta amb un advocat el conflicte GPL i App Store si mai passa a l'App Store públic. Lichess Mobile hi és amb GPL, però el conflicte no s'ha resolt mai.
5. **Política de privacitat** en una URL pública amb un correu de contacte, i etiqueta de privacitat: «No es recullen dades».
6. Per a **provadors externs** cal la revisió beta, amb el text de «Què cal provar» de `metadata.md`.

## Abans d'anar a l'App Store (no fa falta per a TestFlight intern)
- Fer revisar «Scachs» per un advocat de marques: SCACS S.A. té marca a les classes 35/42 i «escacs» pot ser descriptiu.
- Escriure a chess.com (legal@chess.com) per l'ús de la seva API pública en una app. Les seves condicions limiten l'accés automatitzat i no parlen de l'API pública.
- Fer-hi repassar les 30 lliçons per un jugador fort.
- Reajustar el model de classes (`ExpectedPoints`) amb dades CC0 de Lichess.
- Mesurar calor i temps d'anàlisi en un iPhone real i en el més antic que admeti iOS 26.

## Versió
Versió `0.1`. Cada pujada usa un número de build nou automàticament.
