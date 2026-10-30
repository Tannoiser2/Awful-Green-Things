extends RefCounted
## Testi della storia illustrata dell'Epilogo alternativo: titolo e racconto di ognuno dei 35 paragrafi
## (le vignette sono in assets/epilogo/epilogo_NN.webp). Gli esiti dei dadi li aggiunge il motore.

const PAGES := {
	1: ["Che rotta prendiamo?", "La Znutar è ormai un puntino alle spalle. Sul pannello di navigazione si accendono tre rotte: dritti verso Snudl-1, indietro verso l'ultimo pianeta visitato, oppure verso un sistema inesplorato lì vicino. Tutti hanno un'opinione, e tutti la urlano."],
	2: ["Un anno fra le stelle", "Un anno intero di stelle, asteroidi e partite a carte truccate. I motori ronzano, le razioni sanno di cartone e nessuno ricorda più chi ha cominciato a russare per primo."],
	3: ["Terra in vista!", "Un pianeta verde e azzurro riempie l'oblò. Cascate, foreste di funghi giganti e un'aria che si può perfino respirare: la scialuppa scende fra nuvole di vapore."],
	4: ["Alieni ostili!", "Dalle rocce sbucano creature piene di chele e di pessime intenzioni. Ci circondano, schioccano, sbavano. Si può provare a evitarle, attaccarle… o tentare di fare amicizia."],
	5: ["Battaglia!", "È rissa! Pugni, morsi, pistole e il vecchio estintore di bordo che sputa schiuma ovunque. Chi resta in piedi alla fine, vince."],
	6: ["Rifornimento", "Frutti mai visti, sorgenti limpide e perfino un po' di carburante da raffinare. Le stive tornano piene: per un po' nessuno patirà la fame."],
	7: ["Due anni di viaggio", "Due anni lunghi lunghi. C'è chi dorme, chi pilota, chi conta le stelle e chi giura di aver visto un pianeta a forma di ciambella."],
	8: ["Persi nello spazio", "Le carte stellari non tornano, la bussola gira su se stessa e ogni galassia sembra uguale all'altra. Siamo ufficialmente persi."],
	9: ["Il buco nero", "Un vortice nero inghiotte la luce delle stelle e tira, tira, tira. Il pilota stringe la cloche con tutte e due le mani: o di qui o di là."],
	10: ["La nube cosmica", "Una nube luminosa, rosa e azzurra, avvolge la scialuppa. È bellissima. È anche piena di cose che non dovrebbero entrare nei polmoni."],
	11: ["Scomparsi", "Della scialuppa non resta più nulla: inghiottita, svanita, cancellata dalle mappe. Nessuno saprà mai che fine abbia fatto."],
	12: ["Snudl-1!", "Eccola: Snudl-1, con le sue torri, i suoi parchi e le sue code all'ufficio reclami. Si spalanca il portello e la folla corre ad abbracciare i sopravvissuti. Bentornati a casa!"],
	13: ["Uno strano planetoide", "Cristalli viola, rocce sospese a mezz'aria e strade che si attorcigliano su se stesse. Qui niente è come sembra, e niente sembra normale."],
	14: ["Le scorte finiscono", "Quattro anni di viaggio. In dispensa restano un barattolo di Zgwortz e una briciola sospetta. Se non si trova da mangiare entro dieci anni, sarà la fine."],
	15: ["La strana malattia", "Febbre verde, pois gialli, starnuti che fanno tremare le paratie. Una malattia sconosciuta si sparge a bordo: si salvi chi può (e chi ha un buon medico)."],
	16: ["Il relitto alieno", "Un'astronave enorme, nera e silenziosa, galleggia alla deriva. Nessuna luce, nessuna risposta. Si passa oltre… o si sale a dare un'occhiata?"],
	17: ["Riparazioni", "Atterraggio d'emergenza e via con chiavi inglesi, saldatrici e parole poco eleganti. Se c'è un motorista a bordo, forse la scialuppa tornerà a volare."],
	18: ["Naufraghi", "Niente da fare: la scialuppa non si ripara più. Un fuoco acceso fra i rottami, uno sguardo all'orizzonte sconosciuto… e una lunga, lunghissima attesa."],
	19: ["Verso l'ultimo pianeta", "Si torna indietro, verso l'ultimo pianeta visitato: almeno lì si sa cosa aspettarsi. Più o meno."],
	20: ["Danneggiati!", "Scintille, lamiere strappate e un allarme che non vuole saperne di tacere. La scialuppa è danneggiata: bisogna trovare un posto dove ripararla, e in fretta."],
	21: ["Tempesta ionica", "Fulmini azzurri danzano sullo scafo, gli strumenti impazziscono e i capelli di tutti stanno dritti. Benvenuti nella tempesta ionica."],
	22: ["Vita intelligente", "Rovine scolpite, una città scintillante all'orizzonte, strane macchine che pulsano di luce. Qui c'è qualcuno di intelligente. Forse più di noi."],
	23: ["Materia oscura", "Il planetoide è fatto di materia oscura quantizzata negativamente, qualunque cosa voglia dire. Di sicuro vuol dire che sta per esplodere."],
	24: ["Primo contatto", "Disegni, gesti, sorrisi, un cesto di frutta come regalo. Gli alieni ci guardano con i loro tanti occhi: capiranno che veniamo in pace?"],
	25: ["Le difese automatiche", "Il relitto si risveglia di colpo: raggi rossi e missili a ricerca partono da ogni torretta. Altro che nave abbandonata!"],
	26: ["Computer alieni", "Dentro il relitto, consolle che pulsano come organi e schermi pieni di simboli impossibili. Premere qualcosa sarebbe una pessima idea. O forse geniale."],
	27: ["Il portale del tempo", "Un anello di pietra antica, e dentro un vortice azzurro che sussurra di altre epoche. Da qui si potrebbe tornare a casa in un attimo… o perdersi per sempre."],
	28: ["Ai comandi del relitto", "Le consolle aliene rispondono! Con un po' di fortuna (e un buon ufficiale) l'enorme relitto punta dritto verso casa."],
	29: ["Le capre spaziali", "Sorpresa: gli alieni erano malvagie capre spaziali di antimateria, con le corna, la bava e un pessimo carattere. Scappare!"],
	30: ["Un anno alla deriva", "Un altro anno fra campi di asteroidi e soli lontani. Il cannocchiale passa di mano in mano: chissà cosa ci aspetta oltre la prossima stella."],
	31: ["Attraverso il portale", "Il vortice si accende e la scialuppa ci si tuffa dentro. Piramidi, città del futuro, dinosauri: i secoli scorrono fuori dall'oblò."],
	32: ["Tre anni nello spazio", "Tre anni. Anelli di pianeti giganti, comete, e un'infinita partita a dama che nessuno ha intenzione di perdere."],
	33: ["Dritti a casa", "Rotta su Snudl-1, motori al massimo. In fondo allo spazio brilla un puntino azzurro: casa. Ci vorranno almeno due anni."],
	34: ["Un pianeta deserto", "Sabbia, crateri e rocce a perdita d'occhio. Sembra non esserci nessuno… ma qualcosa si muove fra le dune."],
	35: ["Al riparo", "Acquattati dietro le rocce, tutti trattengono il fiato mentre gli alieni passano. Meglio non farsi notare, e ripartire al più presto."],
}

## Le pagine in cui si sceglie (la scelta compare nel libro).
const CHOICES := [1, 4, 16, 22, 26, 27]
