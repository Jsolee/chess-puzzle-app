# Scachs · marca

Scachs és una app d'escacs per a qui els estima i juga poc. El nom és la paraula del poema *Scachs d'amor* (València, c.1475), el registre més antic que es coneix de la dama i l'alfil moderns. Es pronuncia «skaks». Es llegeix sempre amb S gòtica.

## La idea
Peces com a joies d'esmalt. Un fil de metall subjecta l'esmalt i agafa la llum de veritat: quan inclines el telèfon, la llum corre pel fil. En resoldre un puzzle, una ona de llum surt de la casella de l'última jugada i recorre tot el tauler. Això és l'únic moment espectacular. La resta està quieta.

## Logotip
- **Paraula:** `logo/wordmark-*.svg`. Grenze Gotisch Medium convertida a traços, amb tracking -6. No es torna a compondre amb la font.
- **Sigle:** la S gòtica sola, `logo/mark-*.svg`, on la paraula no hi cap. Aguanta a 16 px.
- **Marge:** com a mínim l'alçada de la `c` al voltant.
- **Mida mínima:** paraula 56 px d'ample; S 16 px.
- **Colors:** estany sobre verd, tinta sobre estany, verd sobre estany. Mai daurat sobre estany (no té contrast).
- **No:** contorns, ombres, degradats, inclinar-lo, canviar-li la lletra, posar-lo sobre el tauler.

## Icona
La dama en esmalt sobre verd de Paterna: `pieces/icons.py` la genera i va a `Scachs/Assets.xcassets/AppIcon.appiconset` amb les variants fosca i tenyida.

## Color
Valors exactes a `tokens.json`.
- **Verd de Paterna** `#0f3a33`: el camp de tota l'app. Ve del verd de coure de la ceràmica valenciana del segle XIV, i el verd és l'estendard de Venus al poema.
- **Estany** `#f6f1e6`: text i peces blanques. **Tinta** `#16121c`: peces negres i text sobre estany.
- **Daurat** `#e7b96c`: l'únic accent interactiu. Només sobre verd o tinta.
- **Tauler:** `#ece6d6` i `#2c6f5e`, amb fil `#a9843f` entre caselles.
- **Classes de jugada:** els mateixos noms i llindars que tothom coneix, amb glifs i tons propis.

## Tipografia
- **Grenze Gotisch Medium** per a títols, de 28 pt amunt. Mai per a notació ni dades.
- **Ysabeau Office** per a tota la resta, a 430, 520 i 640. Té xifres tabulars per defecte; la notació va amb ella.
- Els escacs en notació figurina fan servir `Scachs/Resources/Pieces/fig*.png`, perquè cap de les dues fonts té glifs de peces.

## Peces
`pieces/silhouettes.py` és la font de veritat. Robustes, amb base ampla i cap gran, perquè es llegeixin a 40 pt. L'alfil té el tall en diagonal perquè es mou en diagonal.
- Blanques: esmalt d'estany amb fil de bronze fosc, perquè el contorn aguanti sobre casella clara.
- Negres: esmalt de tinta amb fil daurat clar, perquè el contorn aguanti sobre casella fosca.

## Llum i moviment
- La llum surt d'una habitació amb una finestra que es veu reflectida a l'esmalt. Inclinar el telèfon mou l'habitació. L'hora del dia n'escalfa el to.
- Una jugada: 200 ms, sortida suau, sense rebot. So, hàptica i moviment surten junts.
- Només una ona per solució. Si «Redueix el moviment» és actiu, la llum no segueix el telèfon i l'ona es queda en un flaix suau.

## Veu
Català, de tu, en present. Frases curtes que descriuen el que passa. Sense exclamacions, sense culpa, sense presses: qui obre l'app té deu minuts i ha vingut per gust.
- Sí: «Juguen les blanques.» No: «És el teu torn! Resol el puzzle!»
- Sí: «Aquesta forquilla se t'ha escapat tres vegades. Aquí la veuràs de prop.» No: «Millora les teves habilitats avui!»
- Sí: «Fa tres setmanes que no jugaves. El tauler és on el vas deixar.» No: «Has perdut la ratxa.»

## Història: com es pot dir
- Sí: «el registre més antic que es coneix de la dama moderna», «c.1475», «València».
- No: «València va inventar els escacs moderns», «la primera partida», «el manuscrit original». El manuscrit conegut era una còpia i se'n desconeix el parador.
- Reconeix l'origen islàmic del reflex metàl·lic i dels escacs.

## Crèdits
Peces, tauler, logotip i icona: fets per a Scachs. Fonts: Grenze Gotisch i Ysabeau Office, SIL OFL. Motor: Stockfish, GPLv3. Puzzles i obertures: Lichess, CC0.
