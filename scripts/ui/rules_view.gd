extends Control
## Riassunto delle regole (8ª edizione Steve Jackson Games) e scelte di questa versione digitale.
## Si apre dal menu o in partita.

const D = preload("res://scripts/data/agt_data.gd")

var main
var overlay := false

const SECTIONS := [
	["La storia", """La nave esploratrice [b]Znutar[/b] ha preso a bordo un «campione minerale» che era in realtà un uovo. Ora le [b]Cose Verdi[/b] crescono, si moltiplicano e mangiano l'equipaggio. Un giocatore guida le Cose Verdi, l'altro l'equipaggio, armato di oggetti di bordo di cui nessuno sa l'effetto sui mostri."""],
	["Preparazione", """• L'equipaggio si dispone nelle aree di partenza indicate per ciascuno (la Mascotte nella Cabina del Capitano).
• Le Cose Verdi tirano un dado per la popolazione iniziale (da 6 Uova, 4 Piccoli e 2 Adulti fino a 1 Uovo, 6 Piccoli e 4 Adulti) e un dado per l'area del primo mostro: Stiva principale, Laboratorio scientifico, Hangar dell'Esploratore, della Lancia o del Disco (col 6 si sceglie).
• Gli altri si piazzano uno per area, ognuno accanto a un'area già occupata e mai dove c'è l'equipaggio.
• [b]Scoperta[/b]: l'equipaggio muove uno o due membri dentro aree con le Cose Verdi e attacca a mani nude. Poi la partita comincia con il turno dei mostri."""],
	["Le pedine", """Ogni pedina ha [b]dadi d'attacco / costituzione / movimento[/b].
• Adulto 4 / 16 / 2 · Piccolo 2 / 12 / 1 · Frammento 1 / 8 / 0 · Uovo 0 / 5 / 0.
• Un attacco riesce se il totale dei dadi è [b]pari o superiore[/b] alla costituzione del bersaglio. Più attaccanti sullo stesso bersaglio sommano i dadi; ognuno attacca una volta per turno.
• Le pedine sono limitate (12 Adulti, 18 Piccoli, 19 Uova, 22 Frammenti): se finiscono, la crescita si ferma."""],
	["Turno delle Cose Verdi", """1. [b]Crescita[/b]: si sceglie un livello. Frammenti → Piccoli, Uova → Piccoli, Piccoli → Adulti, oppure ogni Adulto depone un Uovo. Chi è stordito non cresce.
2. [b]Movimento[/b]: Adulti fino a 2 aree, Piccoli 1. Ci si ferma entrando in un'area con equipaggio sveglio o con un Recinto acceso; uscire si può sempre.
3. [b]Recinti[/b]: i Recinti accesi colpiscono i mostri nella loro area.
4. [b]Attacco[/b] contro l'equipaggio nella stessa area. Chi viene ucciso è divorato: uno dei mostri che l'hanno attaccato cresce di un livello (un Adulto depone un Uovo). Dove c'è il Robot si può attaccare solo lui; se viene «mangiato» si pesca un gettone effetto e lo si applica al mostro che lo mangia.
5. [b]Risveglio[/b] dei mostri storditi."""],
	["Turno dell'equipaggio", """1. [b]Armi[/b]: chi è in un'area con un'arma la prende (una a testa; la Mascotte no). Chi è nella stessa area può passarsi le armi. Un Recinto acceso si può spegnere a distanza.
2. [b]Movimento[/b]: ognuno fino al suo movimento. Ci si ferma entrando in un'area con Adulti o Piccoli svegli o con un Recinto acceso.
3. [b]Attacco[/b], un'area alla volta: a mani nude nella stessa area, oppure con le armi. Chi è entrato in un'area con Adulti o Piccoli può attaccare solo lì.
4. [b]Risveglio[/b] di chi era stato stordito dal gas nel turno precedente (ha perso un turno intero)."""],
	["Le armi e i gettoni effetto", """La prima volta che un'arma viene usata si pesca un [b]gettone effetto[/b]: vale per quell'arma per il resto della partita (Vetrina delle armi). Se si provano insieme due armi nuove, un solo gettone vale per tutte e due solo per quell'attacco, e non si scopre niente.
Gettoni: 5, 4 o 3 dadi per uccidere · 5 dadi per stordire · Rimpicciolisce (Adulto → Piccolo, Piccolo e Frammento → Uovo, l'Uovo svanisce) · Cresce · 1 dado di Frammenti (il mostro esplode in 1-6 Frammenti) · Nessun effetto (l'arma esce dal gioco).
Ordine degli effetti: Cresce, Rimpicciolisce, dadi per uccidere (con le mani), Frammenti, dadi per stordire.
• [b]Stessa area[/b], un mostro: Siringa, Stecca da biliardo, Saldatrice, Coltello a mano.
• [b]Stessa area o adiacente[/b], un mostro: Acido, Zgwortz (tornano al deposito dopo il lancio).
• [b]Linea di vista[/b]: Pistola stordente (un mostro), Coltello lanciato (un mostro; resta dove cade), Raggio comunicatore (tutti i mostri dell'area).
• [b]Estintore[/b]: tutti i mostri della stessa area o di un'area adiacente.
• [b]Granata a gas[/b] e [b]Carburante[/b]: tutta la sezione colpita (la nube si ferma solo ai portelli, quindi in un corridoio riempie tutti i tratti collegati), equipaggio compreso: il gas fa 5 dadi per stordire (non al Robot), il carburante 5 dadi per uccidere. Tornano al deposito.
• [b]Recinto elettrico[/b]: chi lo porta resta fermo un turno senza attaccare e lo accende nell'area; colpisce i mostri che entrano o restano lì, e tutti devono fermarsi entrando."""],
	["Linea di vista", """Chi sta in un'area vede attraverso i portelli della sua area fino al portello o alla parete successiva; nei corridoi la vista prosegue lungo i tratti dritti collegati da passaggi aperti, mai dietro gli angoli. Le pedine non bloccano la vista. In questa versione le linee di vista sono calcolate sul disegno del tabellone."""],
	["Fuga e autodistruzione", """• [b]Autodistruzione[/b]: il Capitano, il Primo Ufficiale, l'Ufficiale di Macchina o un Pilota passa un turno su uno dei Ponti senza attaccare; la Znutar esplode alla fine del terzo turno successivo dell'equipaggio, con tutti i mostri e chi è ancora a bordo.
• [b]Fuga[/b]: dagli hangar si parte con l'Esploratore (2 posti), il Disco (4) o la Lancia (senza limite); il Robot e la Mascotte non contano e non pilotano. Ogni scialuppa affronta poi l'[b]Epilogo[/b], il lungo viaggio verso Snudl-1."""],
	["Vittoria", """• Se le Cose Verdi si prendono la nave: 111 punti ai mostri (55,5 se la nave si autodistrugge).
• L'equipaggio fa tanti punti quanta è la costituzione dei sopravvissuti tornati a casa (senza Robot e Mascotte); se stermina le Cose Verdi, quella di chi è ancora vivo a bordo.
• Vince chi ha più punti."""],
	["Questa versione", """• Le aree, i portelli, i passaggi e le linee di vista sono stati ricavati dal tabellone; i 2 Barattoli di Zgwortz in più stanno in Mensa, la Tanica in più nel Serbatoio n. 1.
• Le armi da lancio a perdere tornano al deposito più sguarnito; il Coltello lanciato resta nell'area colpita.
• Quando un mostro divora qualcuno, cresce di preferenza un Piccolo, poi un Adulto (che depone l'Uovo), poi un Frammento.
• Le Cose Verdi che crescono quando le pedine non bastano sono scelte in ordine di arrivo.
• Varianti e scenari nel menu: vedi la pagina «Varianti e scenari».
• Gioco online con Firebase: ogni mossa è un passo numerato, tutti i dispositivi giocano la stessa partita."""],
]

const OPTIONAL := [
	["Varianti semplici", """• [b]Un Adulto in più[/b] per le Cose Verdi nella popolazione iniziale.
• [b]Comunicatore a due frequenze[/b]: se il primo effetto delude si prova l'altra frequenza (un nuovo gettone) e poi si usa ogni volta il migliore dei due.
• [b]«Cresce» fa deporre le uova[/b] (edizioni TSR): un Adulto colpito da «Cresce» depone un Uovo."""],
	["Fuori dalla Znutar", """Attorno alla nave c'è lo [b]scafo[/b], diviso in un tratto per ogni stanza del perimetro (i due Serbatoi ne hanno due), e oltre lo scafo quattro [b]zone di spazio[/b]: sopra, a prua, sotto e a poppa.
• [b]Camere stagne[/b] (⇅) nella Stiva, nei tre hangar, nei due Sensori, nel Lancio sonde e in Sala macchine: si passa fra la stanza e il suo tratto di scafo partendo accanto, e passarla prende tutto il movimento. Funzionano anche per le Cose Verdi, ma non entrano se nella stanza c'è equipaggio sveglio; il Capitano o il Primo Ufficiale su un Ponte, all'inizio del turno dei mostri, può chiuderne una (🔒) fino al turno successivo. La Mascotte esce solo con la sua tuta.
• Sullo scafo si cammina come dentro la nave. Le Cose Verdi possono anche essere piazzate fuori all'inizio.
• [b]Tute a reazione[/b] (8: due in ogni hangar e due in Stiva): 1 dado a mani nude, costituzione 20 (i colpi oltre passano a chi è dentro), movimento 1 verso qualunque area vicina, anche nello spazio; chi la indossa posa l'arma e la riprende al turno dopo; immune al gas.
• [b]Carrelli elevatori[/b] (2, in Stiva): 3 dadi, costituzione 40, movimento 1; vanno solo in Stiva, negli hangar e nello spazio; dallo spazio afferrano una Cosa Verde sullo scafo della loro zona e la scagliano via. Possono portare solo il carburante.
• [b]Tuta della Mascotte[/b] (Controllo danni): costituzione doppia, movimento 3, immune al gas.
• Dallo spazio si colpiscono le Cose Verdi sullo scafo della stessa zona e loro non possono rispondere. Fuori l'Estintore e la Granata non funzionano; il Carburante investe tutta la zona.
• [b]Le scialuppe[/b] decollano nello spazio: volano da una zona all'altra, rientrano nel proprio hangar o partono per Snudl-1. Dal Disco e dall'Esploratore si sparano le armi sullo scafo; l'Esploratore e la Lancia possono usare il [b]getto del razzo[/b] (uno o due Carburanti su tutto lo scafo della zona), poi schizzano via per tre turni."""],
	["Revenge of the Awful Green Things", """Regole di Tom Rhoads e James Sterrett, ognuna attivabile dal menu.
• [b]Megadulti[/b]: un Adulto che mangia un membro dell'equipaggio, che è colpito da «Cresce» o che cresce nella fase di crescita (uno solo) tenta la metamorfosi invece di deporre l'Uovo: riesce con un dado pari o inferiore al numero del turno (sempre, se l'equipaggio ha scoperto un'arma ad area che uccide o rimpicciolisce) e pesca un gettone. [b]Melmoso[/b] 5/22/2: scioglie una parete e passa nella stanza accanto lasciando un buco; mangia le armi. [b]Covatrice[/b] 1/22/1 (5 dadi accanto a uova o piccoli): depone un uovo a ogni crescita e, quando crescono gli Adulti, fa crescere i Piccoli, schiudere le Uova o depone 1-6 uova. [b]Lanciafiamme[/b] 2/22/2: 12 dadi di fiamme sull'equipaggio della sua area o 6 su un'area accanto (un Estintore ne toglie 3; chi brucia non si mangia; una Tanica può esplodere). [b]Tentacolone[/b] 8/22/2. [b]Corridore[/b] 4/22/4: porta con sé uova e piccoli. [b]Corazzato[/b] 5/32/2. [b]Tessitore[/b] 4/22/2: tesse ragnatele dove non c'è equipaggio sveglio; chi entra si ferma (la Saldatrice e il Carburante le bruciano). [b]Cervellone[/b] 2/20/3: raccoglie un'arma già usata (1-3 su un dado) e la usa contro l'equipaggio (3 dadi per uccidere; Pistola, Granata e Carburante come di consueto); sul Ponte può avviare l'autodistruzione (con un 1). Gli altri gettoni: «fallimento metabolico» (l'Adulto muore) e «due uova». I Megadulti non depongono uova (tranne la Covatrice) e contano come Adulti; morti, il gettone torna nella tazza.
• [b]Cucina, Mensa e Zgwortz[/b]: nel loro attacco, le Cose Verdi in Cucina o in Mensa senza equipaggio tirano un dado: 1 Cresce, 2 Rimpicciolisce, 3 quattro dadi per uccidere, 4 cinque per stordire, 5-6 un barattolo di Zgwortz. Lo Zgwortz non ha un gettone: ogni barattolo tira (1-2 Cresce, 3 niente, 4 quattro dadi per uccidere, 5 cinque per stordire, 6 reazione allergica mortale).
• [b]Varianti delle armi[/b]: il gettone «1 dado di Frammenti» pescato per scoprire un'arma resta solo con 1-2, altrimenti se ne pesca un altro; un Adulto da solo con un'arma già usata può mangiarla (l'arma esce dal gioco, Zgwortz, Granate e Taniche tornano al deposito) e subisce un gettone a caso; una Tanica che esplode in un Serbatoio con altre taniche lo fa saltare: muore chi c'è dentro, le aree accanto subiscono un'esplosione, il Serbatoio sparisce e l'equipaggio perde 20 punti (se saltano tutti e due, a bordo non si fanno punti).
• [b]Mostri nascosti[/b]: chi guida solo l'equipaggio vede le Cose Verdi solo nelle aree in linea di vista di qualcuno sveglio e le Uova solo nella stessa area o lungo i corridoi aperti; si attaccano solo i mostri visibili."""],
	["Epilogo alternativo", """Al posto dell'Epilogo normale, il viaggio di ogni scialuppa segue una tabella di 35 eventi tirando un d10. Si parte scegliendo la rotta: dritti verso Snudl-1, verso l'ultimo pianeta visitato o verso un sistema inesplorato.
• La scialuppa può restare [b]senza scorte[/b] (dopo altri dieci anni senza rifornimenti l'equipaggio muore di fame), [b]danneggiata[/b] o [b]persa[/b]: ognuna di queste condizioni peggiora alcuni tiri.
• Incontri con alieni ostili o intelligenti (evitare, attaccare o comunicare), buchi neri, nubi cosmiche, tempeste ioniche, malattie, relitti alieni, un portale temporale e le malvagie capre spaziali di antimateria.
• Alcuni membri aiutano: il Pilota, il Capitano, il Primo Ufficiale, il Dottore e l'Infermiere, il Marconista, il Tecnico, il Motorista e l'Ufficiale di Macchina. In battaglia la Pistola, il Carburante o la Granata aggiungono i dadi di un gettone pescato a caso.
• Chi resta naufrago su un pianeta abitabile conta per metà dei punti."""],
	["Solitario: il Capitano Yid", """Il Capitano torna sulla Znutar con il Disco e trova tutti addormentati: le Cose Verdi sono in letargo e l'equipaggio è la loro dispensa.
• [b]Preparazione[/b]: tutto l'equipaggio (tranne il Capitano) e tutte le Cose Verdi, Frammenti compresi, sono [b]pedine coperte[/b] mescolate: una in ogni area tranne gli hangar, due in più dove si trovano armi, altre due in Controllo danni e nelle due Officine, quattro in più su ogni Ponte e il resto in Sala macchine. Il Capitano parte dall'Hangar del Disco. Un Estintore, un Comunicatore e il gettone «5 dadi per uccidere» escono dal gioco.
• [b]Turno[/b]: prima l'equipaggio (armi, movimento, [b]allarme[/b], attacco), poi le Cose Verdi sveglie. Chi entra in un'area con pedine coperte si ferma; nell'allarme si scoprono: le Cose Verdi si svegliano e attaccano subito, i membri dell'equipaggio restano [b]prigionieri nella melma[/b] finché nella loro area c'è l'equipaggio e non ci sono più Cose Verdi.
• Se in un turno non si sveglia niente, si sveglia da sola la pedina più lontana dall'equipaggio.
• [b]La carica finale[/b]: entrando in Controllo danni, su un Ponte, in un'Officina o in Sala macchine, alla fine del turno successivo dell'equipaggio si scopre tutto.
• [b]Le Cose Verdi[/b] si muovono da sole: [b]crescono tutte[/b] ogni turno (se ci sono pedine libere), inseguono il membro più vicino e attaccano tutte insieme il più debole (il Robot per primo). Mangia la Cosa Verde più grossa che può crescere; «Cresce» fa deporre le uova anche agli Adulti.
• Niente fuga né autodistruzione: si vince sterminando tutte le Cose Verdi, e i punti sono la costituzione dei sopravvissuti. Si perde se non resta nessuno sveglio."""],
	["Ammutinamento (3 giocatori)", """Il Primo Ufficiale si è ribellato: la [b]squadra del Capitano[/b] (blu: gli Snudliani gialli, gli Smbaliti, metà dei Redundani, la Mascotte e all'inizio il Robot) tiene la prua e il Ponte n. 1, quella del [b]Primo Ufficiale[/b] (arancione: i Frathm, gli Snudliani verdi e gli altri Redundani) la poppa e il Ponte n. 2. Le due squadre non cooperano.
• Ogni squadra si dispone nelle sue aree di partenza. Le Cose Verdi sono meno (da 3 Uova, 2 Piccoli e 2 Adulti a 1 Uovo, 3 Piccoli e 3 Adulti; al massimo 8 Adulti, 12 Piccoli, 14 Uova e 15 Frammenti). Un dado decide chi le scopre: 1-2 il Capitano, 3-4 il Primo Ufficiale, 5-6 entrambi con un membro a testa.
• [b]Turno[/b]: Cose Verdi, poi la squadra del Capitano, poi quella del Primo Ufficiale. Le armi si prendono solo dove non ci sono avversari; i compagni possono scambiarsele. Una Siringa sta in Infermeria e l'altra al Supporto vitale.
• [b]Combattere fra equipaggi[/b]: a mani nude o con le armi, con effetti fissi: Saldatrice e Stecca 3 dadi per uccidere, Coltello e Acido 4, Carburante 5, Pistola e Granata 5 dadi per stordire, la Siringa dimezza il movimento del bersaglio per un turno; Comunicatore, Estintore, Zgwortz e Recinto non fanno niente. Il Dottore e l'Infermiere con la Siringa possono invece risvegliare un compagno stordito (senza attaccare).
• [b]Il Robot[/b] obbedisce a chi ha il [b]Telecomando[/b] (in Officina) e lo vede; il [b]Disturbatore[/b] (nell'Officina di poppa) lo blocca se chi lo porta è nella sua area. Senza padrone non si muove e non attacca.
• Autodistruzione dal proprio Ponte (Capitano, Ufficiale di Macchina o Pilota giallo dal n. 1; Primo Ufficiale, Pilota blu o Ufficiale Operativo dal n. 2). Ogni squadra fugge con le sue scialuppe.
• [b]Vittoria[/b]: ogni squadra conta la costituzione dei suoi sopravvissuti (a bordo se le Cose Verdi sono sterminate, o tornati a casa dall'Epilogo), senza Robot e Mascotte. Se le Cose Verdi fanno più punti delle due squadre insieme vincono loro, altrimenti vince la squadra con più punti."""],
]

var page := 0
var cols: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not overlay:
		add_child(UI.Starfield.new())
	else:
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.8)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(bg)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.comic_style(UI.CREAM, 16))
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 70
	box.offset_right = -70
	box.offset_top = 30
	box.offset_bottom = -30
	add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var t := UI.title("Le regole", 54)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(t)
	for i in 2:
		var tb := UI.button(["Regole base", "Varianti e scenari"][i], 260, 56, 24)
		var ii := i
		tb.pressed.connect(func():
			page = ii
			_fill())
		hb.add_child(tb)
	var sp := Control.new()
	sp.custom_minimum_size.x = 20
	hb.add_child(sp)
	var close := UI.primary(UI.button("Chiudi" if overlay else "Indietro", 200, 56, 26))
	close.pressed.connect(func():
		if overlay:
			queue_free()
		else:
			main.show_menu())
	hb.add_child(close)
	cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	_fill()


func _fill() -> void:
	for c in cols.get_children():
		c.queue_free()
	var src: Array = SECTIONS if page == 0 else OPTIONAL
	var half := 5 if page == 0 else 3
	for part in [src.slice(0, half), src.slice(half)]:
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rt.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rt.add_theme_color_override("default_color", UI.INK)
		rt.add_theme_font_size_override("normal_font_size", 19)
		rt.add_theme_font_size_override("bold_font_size", 19)
		rt.add_theme_font_override("bold_font", UI.font_bold)
		var txt := ""
		for s in part:
			txt += "[font=res://assets/fonts/Bangers-Regular.ttf][font_size=30][color=#d2321e]%s[/color][/font_size][/font]\n%s\n\n" % [s[0], s[1]]
		rt.text = txt
		cols.add_child(rt)
