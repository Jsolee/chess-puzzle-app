# Scachs: TestFlight i App Store Connect

## Ja fet
- `Scachs/App/PrivacyInfo.xcprivacy`: sense seguiment ni dades recollides. `UserDefaults` declarat (CA92.1). El binari no importa cap API de temps de fitxer.
- `ITSAppUsesNonExemptEncryption = NO`: només s'usa l'HTTPS del sistema.
- Icona de 1024 px sense alfa, amb variants fosca i tenyida.
- Textos de la fitxa en tres idiomes a `metadata.md`. Política de privacitat a `privacy.md`.
- Bundle `com.jsolee.scachs`, equip `MUY564KAW3`, iOS 26+, només iPhone.
- `scripts/testflight.sh`: arxiva en Release i puja. El número de build és la data i l'hora.
- App creada a App Store Connect: «Scachs: Chess Puzzles & Review», SKU `scachs`, idioma català. Primera build interna pujada el 2026-10-31.

## T'ho cal fer a tu
1. **Pujar una build nova:** `scripts/testflight.sh`. Signa amb el compte de Xcode (Ajustes > Comptes). L'app ja existeix (6829113197) i el grup intern «Scachs intern» la rep sol, amb distribució automàtica.
2. **Si la pujada falla amb «No Accounts» o «Failed to Use Accounts»:** torna a iniciar sessió a Xcode i mira si Apple demana acceptar un contracte nou a developer.apple.com/account.
3. **Abans de provadors externs (GPL):**
   - Puja el codi: el repo ha de ser públic amb l'etiqueta exacta de la build. Substitueix `[URL DEL REPO]` a `metadata.md`.
   - Consulta amb un advocat el conflicte GPL i App Store si mai passa a l'App Store públic. Lichess Mobile hi és amb GPL, però el conflicte no s'ha resolt mai.
4. **Política de privacitat** en una URL pública amb un correu de contacte, i etiqueta de privacitat: «No es recullen dades».
5. Per a **provadors externs** cal la revisió beta, amb el text de «Què cal provar» de `metadata.md`.

## Abans d'anar a l'App Store (no fa falta per a TestFlight intern)
- Indicar la condició de comerciant (Reglament de Serveis Digitals de la UE) a App Store Connect.
- Fer revisar «Scachs» per un advocat de marques: SCACS S.A. té marca a les classes 35/42 i «escacs» pot ser descriptiu.
- Escriure a chess.com (legal@chess.com) per l'ús de la seva API pública en una app. Les seves condicions limiten l'accés automatitzat i no parlen de l'API pública.
- Fer-hi repassar les 30 lliçons per un jugador fort.
- Mesurar calor i temps d'anàlisi en un iPhone real i en el més antic que admeti iOS 26.

## Versió
Versió `0.1`. Cada pujada usa un número de build nou automàticament.
