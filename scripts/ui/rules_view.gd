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
• Varianti nel menu: un Adulto in più ai mostri; il Comunicatore a due frequenze; «Cresce» che fa deporre le uova come nelle edizioni TSR.
• Gioco online con Firebase: ogni mossa è un passo numerato, tutti i dispositivi giocano la stessa partita."""],
]


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
	var close := UI.primary(UI.button("Chiudi" if overlay else "Indietro", 200, 56, 26))
	close.pressed.connect(func():
		if overlay:
			queue_free()
		else:
			main.show_menu())
	hb.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 30)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(cols)
	var half := 5
	for part in [SECTIONS.slice(0, half), SECTIONS.slice(half)]:
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
