# Scachs: pujar-la a l'App Store

Tot el que va dins del codi ja està fet. Aquesta guia és la part que es fa a App Store Connect, amb el valor exacte de cada camp.

## 0. Abans de res (cal fer-ho tu)
1. **Codi públic (GPL).** Stockfish és GPLv3: el codi de la versió que es publica ha de ser al repo públic. Fusiona `native` a `master`, puja-ho i posa-hi una etiqueta amb la versió (`v1.0`). L'enllaç «Codi font» de *Sobre Scachs* apunta a `https://github.com/Jsolee/chess-puzzle-app`.
2. **Consulta legal**, abans de la primera publicació:
   - La FSF considera que les condicions de l'App Store topen amb la GPL (cas VLC, 2011). Lichess Mobile hi és amb Stockfish, però ningú no ho ha resolt en un jutjat.
   - El nom: SCACS S.A. té marca a les classes 35 i 42. «Escacs» és descriptiu, però val la pena confirmar-ho.
3. **Provar-la en un iPhone real** des de TestFlight: anàlisi, calor, memòria i el mode a cegues amb el mòbil bloquejat.

## 1. Build
`scripts/testflight.sh` arxiva, signa i puja. La versió és 1.0 i la build, la data i l'hora. A App Store Connect, a la versió 1.0, tria aquesta build.

## 2. Informació de l'app
| Camp | Valor |
|---|---|
| Nom | Scachs: Chess Puzzles & Review |
| Subtítol | Escacs, per plaer (ca) · Ajedrez, por placer (es) · Chess, for pleasure (en) |
| Categoria | Jocs > Tauler. Secundària: Educació |
| Drets de contingut | Sí que mostra contingut de tercers, i tens dret a fer-ho: partides públiques que l'usuari importa amb el seu nom, i puzzles i noms d'obertures de Lichess, que són CC0. |
| URL de privacitat | https://github.com/Jsolee/chess-puzzle-app/blob/master/AppStore/privacy.md |
| URL d'assistència | https://github.com/Jsolee/chess-puzzle-app/issues |
| URL de màrqueting | https://github.com/Jsolee/chess-puzzle-app |

Textos, paraules clau i text promocional en tres idiomes: `metadata.md`.

## 3. Classificació per edats
Respon «No» o «Cap» a tot: violència, contingut sexual, llenguatge, drogues, apostes, terror, contingut mèdic, accés web lliure i contingut generat per usuaris. No té xat, compres ni anuncis. Resultat: **4+**.

## 4. Privacitat de l'app
- «Recopileu dades d'aquesta app?» → **No, no recopilem dades**. Etiqueta: *Data Not Collected*.
- L'usuari escriu el seu nom de chess.com o de Lichess i l'app el fa servir per demanar les seves partides públiques directament a aquests serveis. No passa per cap servidor nostre i no surt del dispositiu per a res més. No es considera recollida de dades.

## 5. Preu i disponibilitat
Gratuïta, a tots els territoris. Sense compres dins l'app.

## 6. Captures de pantalla
`AppStore/screenshots/ca`, `es` i `en` contenen nou captures cadascuna, de 1206 × 2622, amb l'app en l'idioma de la carpeta. És la mida que App Store Connect demana com a obligatòria («iPhone con Dynamic Island, pantalla mediana»), i Apple la fa servir per a les altres mides d'iPhone. Puja-les en l'ordre del nom del fitxer, cada carpeta al seu idioma: la 01 és la portada i la resta mostren l'app en ús. Per refer-les: compila en Debug, obre l'app al simulador amb `-scene <escena> -toured YES -AppleLanguages "(ca)"` per a cada escena de `Scachs/App/ScreenshotScene.swift`, desa les captures com `<idioma>-<escena>.png` i passa `python3 tools/store_screenshots.py <carpeta>`. El disseny és a `tools/store_screenshots.html`: un sol panorama de nou captures amb una serp de mar d'esmalt que travessa les tres primeres. Chrome el pinta captura a captura.

## 7. Informació per a la revisió d'Apple
- **Inici de sessió:** no cal. L'app no té comptes.
- **Notes** (enganxa-les en anglès):

> Scachs needs no account. Everything runs on the device: the Stockfish engine, puzzles and lessons.
> To try game import, open Games, tap the people icon and enter the public chess.com username "erik", then tap Done. The app fetches that user's public games from the chess.com Published-Data API. Open any game to see the on-device analysis.
> Background modes: "processing" runs the analysis of imported games overnight while charging (BGProcessingTask). "audio" is for Blindfold mode (Today > Blindfold, with earbuds): it reads puzzles aloud with speech synthesis and takes answers from earbud clicks while the phone is locked in a pocket.
> The app is free software under GPLv3; the source is at https://github.com/Jsolee/chess-puzzle-app. Not affiliated with chess.com or Lichess.

- **Contacte:** el teu nom i telèfon (te'ls demana App Store Connect).

## 8. Exportació
Ja està declarat al binari (`ITSAppUsesNonExemptEncryption = NO`): App Store Connect no ho tornarà a preguntar.

## 9. Enviar
Desa, «Afegeix per a revisió» i envia. Tria «Publicació manual» per decidir tu el dia.
