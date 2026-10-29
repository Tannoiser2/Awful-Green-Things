# The Awful Green Things from Outer Space — versione digitale (Godot 4)

Versione digitale del classico di **Tom Wham** pubblicato da **Steve Jackson Games** (8ª edizione).
Sull'astronave esploratrice **Znutar** un «campione minerale» si rivela un uovo: le **Cose Verdi** si
schiudono, crescono e mangiano l'equipaggio, che si difende con gli oggetti di bordo… senza sapere che
effetto avranno sui mostri. Grafica (tabellone e pedine) dal modulo Tabletop Simulator; tema da fumetto
spaziale con i caratteri Luckiest Guy, Bangers e Comic Neue.

La pubblicazione non parte da sola: Actions → **Pubblica** → *Run workflow*
(ludoteca privata su `awfulgreen.ludoteca-digitale.com` con i segreti Cloudflare, e GitHub Pages finché il
repository è pubblico).

## Avvio
1. Apri Godot 4 (testato su 4.7) → *Importa* → seleziona `project.godot`.
2. Premi **F5**. F11 alterna schermo intero e finestra.

## Cosa c'è
- **Due lati**, ognuno persona o IA (facile, normale, difficile): l'Equipaggio e le Cose Verdi. Con due persone
  allo stesso schermo si gioca a turno.
- **Tutte le regole del gioco base** (8ª edizione): disposizione dell'equipaggio, popolazione e piazzamento
  iniziale dei mostri, scoperta, crescita (con i limiti delle pedine), movimento con gli arresti, recinti
  elettrici, attacchi a mani nude e con le 12 armi, gettoni effetto scoperti alla prima prova (e le armi nuove
  provate insieme), ordine degli effetti (Cresce, Rimpicciolisce, uccidere, Frammenti, stordire), linea di vista,
  gas e carburante che riempiono la sezione fino ai portelli, regola del Robot, mostri divorati che crescono,
  armi da lancio che tornano al deposito, autodistruzione, fuga con le tre scialuppe, **Epilogo** del viaggio
  verso Snudl-1 e punti vittoria.
- **Varianti** dal menu: un Adulto in più per le Cose Verdi; il Comunicatore a due frequenze; «Cresce» che fa
  deporre le uova (regola TSR).
- **Vetrina delle armi** con gli effetti scoperti, **dadi** e **diario di bordo**; onomatopee da fumetto
  (GNAM!, SPLAT!, KABOOM!).
- **Regole** riassunte in italiano dal menu e in partita.

## Comandi
- Rotella per lo zoom, trascina per spostare il tabellone, **Centra** per rifare l'inquadratura.
- Le aree evidenziate sono quelle che si possono scegliere; passando sopra un'area se ne vede il contenuto.
- Movimento: tocca una pedina (o un'area) e poi la destinazione in giallo.
- Attacchi: tocca un'area in rosso, scegli per ognuno arma e bersaglio (le lettere sulle pedine), **Attacca!**.
  **Suggerisci** propone il piano dell'IA, che puoi modificare.

## Gioco online
Dal menu, **Gioca online** (anche dalla versione web). Usa lo stesso progetto Firebase degli altri giochi
(Realtime Database), con le stanze sotto `awfulgreen/rooms`: la sezione generica `$game` delle regole del
database (già pubblicata con Titans, El Grande e Ghouls) lo copre, non serve toccare le regole.

- **Chi crea la stanza** scrive il nome, sceglie quale lato gioca, preme *Crea una stanza* e comunica il codice
  di 4 lettere. Quando l'amico è entrato preme *Inizia online*.
- **L'amico** scrive il nome e il codice e preme *Entra*.
- Ogni decisione è una mossa numerata nel database: i due dispositivi fanno girare lo stesso motore con lo
  stesso seme, quindi la partita è identica. Se cade la linea si rientra con lo stesso codice; se un giocatore
  tace per un minuto, al suo posto gioca l'IA finché non rientra.

## Il tabellone
Le 45 aree della Znutar (stanze, corridoi, hangar), i portelli, i passaggi aperti fra i tratti di corridoio,
le linee di vista e i punti dove appoggiare le pedine sono stati ricavati dal disegno del tabellone:
- `tools/pulisci_aree.py`, `tools/linee_di_vista.py`, `tools/genera_aree.py` (Python + OpenCV) producono
  `assets/data/aree.json` e `assets/board/nave.webp` dalla scansione del tabellone (non nel repository).
- Portelli e passaggi sono elencati in `tools/genera_aree.py` (PAIRS e OPEN): per correggere un collegamento
  basta modificarli e rilanciare lo script.

## Scelte di questa versione (da verificare)
- Armi: delle tre Zgwortz due stanno in Mensa e una in Cucina; delle tre Taniche due nel Serbatoio n. 1.
- Le armi da lancio a perdere tornano al deposito più sguarnito; il Coltello lanciato resta nell'area colpita.
- Quando un mostro divora qualcuno cresce di preferenza un Piccolo, poi un Adulto (depone l'Uovo), poi un
  Frammento. Se le pedine non bastano per far crescere tutti, crescono i primi arrivati.
- Recinto: se due recinti accesi sono nella stessa area, scaricano una volta sola.
- L'autodistruzione si avvia con un'azione al posto del movimento (il membro resta fermo e non attacca).
- Le regole «Fuori dalla Znutar», il solitario e le regole per 3-4 giocatori non ci sono ancora.

## Struttura
```
scripts/data/agt_data.gd     equipaggio, mostri, armi, gettoni, tabelle
scripts/core/engine.gd       motore delle regole (nessuna dipendenza dalla UI)
scripts/core/ai.gd           IA dell'Equipaggio e delle Cose Verdi
scripts/net/                 Firebase (REST) e partita online in lockstep
scripts/ui/                  menu, tabellone (board_view.gd), vista di gioco, regole
tests/sim.gd                 godot --headless --path . -s tests/sim.gd -- 30 1 1   (partite IA contro IA)
tests/shot.gd                xvfb-run godot --path . -s res://tests/shot.gd -- crew   (screenshot)
```

## Crediti
The Awful Green Things from Outer Space © Tom Wham; Steve Jackson Games. Versione digitale per uso privato.
Caratteri: Luckiest Guy (Astigmatic, Apache 2.0), Bangers e Comic Neue (SIL Open Font License).
