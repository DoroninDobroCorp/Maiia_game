"""Rebuild the authored, offline JSON snapshots. No saves or outside files used."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def write(name, value):
    (ROOT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

# One base lexeme per row. Conjugated forms are accepted variants, not new words.
ROWS = '''hola|привет|Hola, Nora.|Привет, Нора.
gracias|спасибо|Gracias, Nora.|Спасибо, Нора.
sí|да|Sí, gracias.|Да, спасибо.
no|нет|No, gracias.|Нет, спасибо.
nombre|имя|Mi nombre es Maya.|Меня зовут Майя.
yo|я|Yo soy Nora.|Я Нора.
tú|ты|Tú eres Maya.|Ты Майя.
amiga|подруга|Mi amiga es Nora.|Моя подруга — Нора.
casa|дом|Mi casa.|Мой дом.
carta|письмо|Una carta para mi amiga.|Письмо моей подруге.
agua|вода|Agua, gracias.|Воду, спасибо.
pan|хлеб|Pan, gracias.|Хлеб, спасибо.
leche|молоко|Pan y leche.|Хлеб и молоко.
té|чай|Té, gracias.|Чай, спасибо.
queso|сыр|Pan y queso.|Хлеб и сыр.
repetir|повторить|¿Puedes repetir?|Можешь повторить?
escuchar|слушать|Quiero escuchar.|Хочу послушать.
despacio|медленно|Más despacio, gracias.|Помедленнее, спасибо.
perdón|извини; простите|Perdón, ¿puedes repetir?|Прости, можешь повторить?
entender|понимать|No entiendo.|Я не понимаю.
café|кофе; кафе|Un café, gracias.|Кофе, спасибо.
jugo|сок|Quiero jugo.|Хочу сок.
sopa|суп|Quiero sopa.|Хочу суп.
dulce|сладкий|El jugo es dulce.|Сок сладкий.
querer|хотеть|Quiero pan.|Хочу хлеб.
mesa|стол|La carta está en la mesa.|Письмо на столе.
silla|стул|Una silla para mi amiga.|Стул для моей подруги.
caja|коробка|La caja está en la mesa.|Коробка на столе.
llave|ключ|La llave está en la caja.|Ключ в коробке.
puerta|дверь|La llave de la puerta.|Ключ от двери.
papel|бумага|Papel para una carta.|Бумага для письма.
lápiz|карандаш|Un lápiz en la mesa.|Карандаш на столе.
libro|книга|El libro está en la caja.|Книга в коробке.
bolsa|сумка; пакет|Una bolsa de papel.|Бумажный пакет.
cinta|лента; скотч|La cinta está en la caja.|Лента в коробке.
rojo|красный|Una caja roja.|Красная коробка.
azul|синий|Un lápiz azul.|Синий карандаш.
verde|зелёный|Una puerta verde.|Зелёная дверь.
grande|большой|Una mesa grande.|Большой стол.
pequeño|маленький|Una caja pequeña.|Маленькая коробка.
abrir|открыть|Abrir la caja.|Открыть коробку.
cerrar|закрыть|Cerrar la puerta.|Закрыть дверь.
poner|положить; поставить|Poner el libro en la mesa.|Положить книгу на стол.
sacar|достать; вынуть|Sacar el lápiz de la caja.|Достать карандаш из коробки.
ayudar|помочь|Quiero ayudar.|Хочу помочь.
mi|мой; моя|Mi libro.|Моя книга.
favorito|любимый|Mi libro favorito.|Моя любимая книга.
nuevo|новый|Un lápiz nuevo.|Новый карандаш.
viejo|старый|Un libro viejo.|Старая книга.
suave|мягкий; нежный|Papel suave.|Мягкая бумага.
río|река|El río es azul.|Река синяя.
cascada|водопад|Una cascada grande.|Большой водопад.
montaña|гора|Una montaña grande.|Большая гора.
árbol|дерево|Un árbol verde.|Зелёное дерево.
piedra|камень|Una piedra pequeña.|Маленький камень.
largo|длинный|Un río largo.|Длинная река.
corto|короткий|Un lápiz corto.|Короткий карандаш.
alto|высокий|Un árbol alto.|Высокое дерево.
bajo|низкий|Una mesa baja.|Низкий стол.
lejos|далеко|La montaña está lejos.|Гора далеко.
luz|свет|La luz de mi casa.|Свет моего дома.
sombra|тень|La sombra del árbol.|Тень дерева.
línea|линия|Una línea azul.|Синяя линия.
color|цвет|Mi color favorito.|Мой любимый цвет.
dibujo|рисунок|Un dibujo del río.|Рисунок реки.
hoy|сегодня|Hoy hay sol.|Сегодня солнечно.
mañana|завтра; утро|Mañana hay lluvia en la historia.|В истории завтра дождь.
sol|солнце|El sol y la montaña.|Солнце и гора.
lluvia|дождь|Hoy hay lluvia.|Сегодня дождь.
viento|ветер|Hay viento.|Ветрено.
aquí|здесь|Aquí está mi dibujo.|Вот мой рисунок.
allí|там|Allí está el río.|Там река.
cielo|небо|El cielo es azul.|Небо синее.
nube|облако|Una nube grande.|Большое облако.
valle|долина|Un dibujo del valle.|Рисунок долины.
llegar|приходить; прибывать|Nora llega a casa.|Нора приходит домой.
buscar|искать|Nora busca la llave.|Нора ищет ключ.
encontrar|находить|Nora encuentra la llave.|Нора находит ключ.
llevar|нести; брать с собой|Nora lleva la carta.|Нора несёт письмо.
volver|возвращаться|Nora vuelve a casa.|Нора возвращается домой.
izquierda|лево; левая сторона|A la izquierda.|Налево.
derecha|право; правая сторона|A la derecha.|Направо.
delante|впереди|Delante de la mesa.|Перед столом.
detrás|позади|Detrás de la caja.|За коробкой.
caminar|идти пешком|Caminar a la derecha.|Идти направо.
uno|один|Un lápiz.|Один карандаш.
dos|два|Dos cartas.|Два письма.
tres|три|Tres piedras.|Три камня.
más|больше; ещё|Más luz.|Больше света.
menos|меньше|Menos viento.|Меньше ветра.
ver|видеть|Veo el río.|Я вижу реку.
oír|слышать|Oigo la lluvia.|Я слышу дождь.
sentir|чувствовать|Siento el viento.|Я чувствую ветер.
elegir|выбирать|Elijo mi dibujo favorito.|Я выбираю любимый рисунок.
contar|рассказывать; считать|Quiero contar una historia.|Хочу рассказать историю.
voz|голос|La voz de Nora.|Голос Норы.
mensaje|сообщение|Un mensaje para mi amiga.|Сообщение моей подруге.
historia|история|Mi historia del valle.|Моя история долины.
junto|вместе; рядом|Juntos en la estación.|Вместе на станции.
hasta|до|¡Hasta mañana!|До завтра!'''

VARIANTS = {"amiga": ["amigo", "amigas", "amigos"], "repetir": ["repite", "repetís", "repetir"], "entender": ["entiendo", "entendés"], "querer": ["quiero", "querés", "quiere"], "rojo": ["roja", "rojos", "rojas"], "pequeño": ["pequeña"], "favorito": ["favorita"], "nuevo": ["nueva"], "viejo": ["vieja"], "largo": ["larga"], "corto": ["corta"], "alto": ["alta"], "bajo": ["baja"], "llegar": ["llega"], "buscar": ["busca"], "encontrar": ["encuentra"], "llevar": ["lleva"], "volver": ["vuelve"], "uno": ["un", "una"], "ver": ["veo"], "oír": ["oigo"], "sentir": ["siento"], "elegir": ["elijo"], "contar": ["cuento"], "junto": ["juntos", "juntas", "junta"]}
CHANNELS = ["Знакомство и радиокафе", "Дом и мастерская", "Долина и вода", "Действия и маленькие истории"]
lexemes = []
for i, row in enumerate(ROWS.splitlines()):
    base, translation, example, gloss = row.split("|")
    lexemes.append(dict(lexeme_id=f"es_{i+1:03}", channel_id=f"es_channel_{i//25+1:02}", base_form=base, lemma=base, translation=translation, accepted_variants=list(dict.fromkeys([base]+VARIANTS.get(base, []))), example=example, example_translation=gloss, topics=[CHANNELS[i//25]], status="not_met", normalization={"casefold": True, "trim_spaces": True, "preserve_diacritics": True}, support_text=translation))
assert len(lexemes) == len({x["base_form"] for x in lexemes}) == 100
by_word = {x["base_form"]: x["lexeme_id"] for x in lexemes}
def refs(*words): return [by_word[w] for w in words]
write("lexicons/es_first_100.json", {"schema_version": 2, "lexicon_id": "es_first_100_r1", "language": "es-AR", "counting_rule": "unique_lexeme_id", "lexemes": lexemes})

def item(key, text): return dict(id=key, text=text)
def field(key, label, required=True): return dict(id=key, label=label, required=required)
def interaction(key, kind, title, prompt, hints, config, success="Эта часть истории сохранена. Можно продолжить или вернуться позже."):
    assert len(hints) == 3
    return dict(interaction_id=key, type=kind, title=title, prompt=prompt, hints=hints, config=config, success_text=success)
def choose(key, title, prompt, choices, required, hints, minimum=None, maximum=None):
    return interaction(key,"assemble_selection",title,prompt,hints,dict(items=[item(k,t) for k,t in choices],required_ids=required,min_selected=len(required) if minimum is None else minimum,max_selected=len(required) if maximum is None else maximum,ordered=False))
def match(key,title,prompt,pairs,hints):
    cards=[item(f"card_{i+1}",p[0]) for i,p in enumerate(pairs)]
    targets=[item(f"target_{i+1}",p[1]) for i,p in enumerate(pairs)]
    return interaction(key,"match_cards",title,prompt,hints,dict(cards=cards,targets=targets[1:]+targets[:1],accepted_pairs={c['id']:f"target_{i+1}" for i,c in enumerate(cards)},pair_feedback={c['id']:f"{pairs[i][0]} — {pairs[i][1]}" for i,c in enumerate(cards)}))
def order(key,title,prompt,fragments,hints):
    ids=[f"fragment_{i+1}" for i in range(len(fragments))]
    cards=[item(k,t) for k,t in zip(ids,fragments)]
    return interaction(key,"order_fragments",title,prompt,hints,dict(fragments=cards[1:]+cards[:1],accepted_orders=[ids]))
def dialogue(key,title,prompt,steps,hints):
    nodes=[]
    for i,(speaker,line,options) in enumerate(steps):
        node_id=f"node_{i+1}"
        nodes.append(dict(node_id=node_id,speaker=speaker,text=line,choices=[dict(id=f"choice_{j+1}",text=text,correct=correct,next_node_id=(f"node_{i+2}" if i+1<len(steps) else "end") if correct else node_id,feedback=feedback) for j,(text,correct,feedback) in enumerate(options)]))
    nodes.append(dict(node_id="end",speaker="Нора" if not steps else steps[-1][0],text="Сообщение дошло. Оставим его в альбоме; продолжить можно в любой день.",terminal=True,choices=[]))
    return interaction(key,"scripted_dialogue",title,prompt,hints,dict(start_node_id="node_1",nodes=nodes))
def inspect(key,title,prompt,details,hints):
    return interaction(key,"inspect_reveal",title,prompt,hints,dict(details=[dict(id=k,title=t,text=d) for k,t,d in details],required_detail_ids=[x[0] for x in details]))
def compose(key,title,prompt,choices,hints,fields=None,sources=None):
    return interaction(key,"exhibit_composition",title,prompt,hints,dict(choices=[item(k,t) for k,t in choices],min_selected=1,max_selected=1,fields=fields or [field("caption","Моя подпись",False)],source_stage_ids=sources or []))
def real(key,title,prompt,criteria,fields,materials,hints,**extra):
    return interaction(key,"real_world_step",title,prompt,hints,dict(criteria=criteria,fields=fields,materials=materials,**extra))

I={}
def add(value): I[value['interaction_id']]=value; return value['interaction_id']
E=[]
def envelope(n,title,story,values,review,reaction):
    keys=[add(v) for v in values]
    new=[x['lexeme_id'] for x in lexemes[(n-1)*5:n*5]]
    E.append(dict(envelope_id=f"es_envelope_{n:02}",number=n,channel_id=f"es_channel_{(n-1)//5+1:02}",title=title,story=story,lexeme_ids=new,review_lexeme_ids=refs(*review),interaction_ids=keys,world_reaction=reaction,real_world_variants=[dict(id="character",title="С готовым персонажем",description="Прочитать или выбрать реплики в этой сцене."),dict(id="together",title="Вместе",description="Разыграть эту же ситуацию с взрослым; говорить вслух необязательно."),dict(id="paper",title="На бумаге",description="Перенести одну реплику или подпись в свой блокнот.")]))

envelope(1,"Имя в эфире","Из приёмника слышен осторожный голос. Нора нашла пустую строчку в журнале: кому отвечает Южный Маяк?",[
 dialogue("es_01_hello","Первый ответ","Выбери приветствие и ответ Норе. Nombre — имя; можно взять название станции.",[("Нора","Hola. Ты хочешь оставить nombre станции в эфире?",[("Hola. Sí, gracias.",True,"Ты поздоровалась и согласилась. Теперь в карточке можно вписать позывной."),("Hola. No, gracias.",True,"Можно пока оставить позывной «Станция». Имя выберешь позже."),("Gracias. Nombre.",False,"Gracias благодарит, nombre называет имя. Сначала поздоровайся словом hola.")])],["Нора сначала здоровается: hola.","Sí — согласие, no — отказ. Оба решения разрешены.","Можно ответить: Hola. Sí, gracias. Позывной вписывается отдельно."]),
 compose("es_callsign","Позывной станции","Выбери основу карточки; имя можно написать или оставить на потом.",[("station","Имя моей станции"),("light","Свет долины"),("own","Свой позывной")],["Посмотри на табличку своей станции.","Позывной помогает узнать отправителя; он не проверка испанского.","Можно выбрать «Имя моей станции» и ничего не записывать голосом."],[field("callsign","Позывной",False)])],[],"Теперь я знаю, как зовётся твоя станция. Оставлю это имя в журнале эфира.")
envelope(2,"Две перепутанные открытки","Нора подписала два конверта одинаково. На одном дом, на другом подруга с письмом. Помоги вернуть маленьким сообщениям их место.",[
 match("es_02_postcards","Кому открытка?","Подбери подписи: yo — я, tú — ты, amiga — подруга. Soy/eres означают «я/ты есть».",[("Yo soy Nora.","Карточка, где Нора представляет себя"),("Tú eres mi amiga.","Карточка обращения к подруге"),("Mi casa.","Рисунок дома"),("Una carta.","Конверт с письмом")],["Ищи слово, которое прямо называет рисунок.","Yo рассказывает о говорящем, tú обращается к собеседнику.","Mi casa подходит к рисунку дома; carta — к письму."])
],['hola','nombre'],"У открыток появились понятные отправители. Нора оставила на обороте маленькую звезду.")
envelope(3,"Поднос у окна","Слушатель пришёл почитать письмо. Он просит pan y leche; Нора по ошибке поставила на поднос чай. Собери нужный заказ.",[
 choose("es_03_tray","Заказ у окна","Pan y leche, gracias. Y означает «и». Поставь на поднос ровно два предмета.",[("water","Agua — вода"),("bread","Pan — хлеб"),("milk","Leche — молоко"),("tea","Té — чай"),("cheese","Queso — сыр")],["bread","milk"],["В просьбе названы два предмета, соединённые y.","Pan — хлеб, leche — молоко. Чая в этом заказе нет.","Поставь pan и leche; остальные карточки оставь на столе."])
],['gracias','carta'],"На столике радиокафе стоит твой первый собранный поднос.")
envelope(4,"Шорох в приёмнике","Шуршащая бумага заглушила часть сообщения. Не нужно угадывать: у радио есть вежливая кнопка переспроса.",[
 dialogue("es_04_repeat","Недостающий кусочек","¿Puedes…? значит «Можешь…?» Выбери просьбу повторить, затем ответь на сообщение.",[("Нора","… pan … [шорох]. Как попросить повторить?",[("Perdón, ¿puedes repetir despacio?",True,"Нора повторяет медленно: Pan y queso, gracias."),("Sí, entiendo.",False,"Это означает «Да, понимаю». Если фрагмент потерялся, можно переспросить."),("No quiero escuchar.",False,"Это «Не хочу слушать». Для переспроса пригодится repetir.")]),("Нора","Pan y queso, gracias.",[("Pan y queso.",True,"Теперь оба предмета названы."),("Pan y leche.",False,"Молоко было в прошлом заказе. Сейчас Нора сказала queso — сыр.")])],["Неясность можно назвать: no entiendo.","Repetir — повторить; despacio — медленно.","Выбери «Perdón, ¿puedes repetir despacio?», затем «Pan y queso»."])
],['pan','queso','leche','gracias'],"Вот недостающий кусочек. Попробуем собрать сообщение ещё раз.")
envelope(5,"Меню маленького кафе","Передача готова открыть первый столик. Ты решаешь, что будет в меню, а Нора пробует заказать суп и сок.",[
 choose("es_05_menu","Моё меню","Оставь sopa и jugo для гостя, а третий пункт выбери сама. Quiero значит «хочу».",[("soup","Sopa — суп"),("juice","Jugo — сок"),("coffee","Café — кофе"),("tea","Té — чай"),("bread","Pan — хлеб")],["soup","juice"],["Заказ Норы — sopa y jugo.","Два нужных пункта обязательны для этой сценки; третий выбираешь ты.","Добавь sopa, jugo и, например, pan."],3,3),
 dialogue("es_05_order","Первый гость","Можно отвечать кнопками или разыграть сцену вместе.",[("Нора","Quiero sopa y jugo. ¿El jugo es dulce? (Сок сладкий?)",[("Sí. Sopa y jugo, gracias.",True,"Заказ соответствует меню. Сладкий — dulce."),("Quiero café.",False,"Это твой заказ кофе. Нора попросила суп и сок.")])],["Сначала найди заказ на своём меню.","Dulce описывает вкус, а не новый предмет.","«Sí. Sopa y jugo, gracias» подтверждает нужные два пункта."])
],['pan','té','gracias'],"Твоё меню появится на столике кафе. Первая часть альбома собрана.")
envelope(6,"Ключ из деревянного ящика","Нора ищет ключ от двери. Она помнит: llave en la caja — ключ в коробке. Осмотри уголок и найди нужное место.",[
 inspect("es_06_drawer","Что где лежит?","En означает «в/на». Открой три подписанных детали, чтобы найти ключ.",[("desk","Mesa y silla","Стол и стул: на столе письмо, под стулом ничего не спрятано."),("box","Caja: llave","В коробке лежит llave — ключ."),("door","Puerta","Нора: теперь ключ можно оставить рядом с дверью, а подпись — в альбоме.")],["Llave — предмет, который ищет Нора.","Она сказала caja, а не mesa или silla.","Осмотри коробку «Caja: llave»; затем подпись двери."])
],['carta','casa'],"Коробка получила бирку llave. Ключ остаётся в учебной сцене.")
envelope(7,"Посылка Тео","Тео просит три вещи для бумажного чертежа: papel, lápiz, cinta. Книга выглядит интересной, но в список не попала.",[
 choose("es_07_parcel","Собрать посылку","Положи в bolsa ровно три вещи из списка Тео.",[("paper","Papel — бумага"),("pencil","Lápiz — карандаш"),("book","Libro — книга"),("bag","Bolsa — сумка"),("tape","Cinta — лента")],["paper","pencil","tape"],["Bolsa — сама сумка, её не кладут внутрь себя.","Список: papel, lápiz, cinta. Libro в нём нет.","Выбери бумагу, карандаш и ленту."])
],['caja','mesa'],"На верстаке появляется посылка с твоей аккуратной описью.")
envelope(8,"Подписи на станции","Таблички с цветами оторвались. На этой учебной картинке есть красная коробка, синий карандаш и зелёная дверь: верни надписи.",[
 match("es_08_labels","Цвет и размер","Цвета названы словами, поэтому цвет экрана не нужен. Roja — форма rojo для caja.",[("Caja roja","Красная коробка"),("Lápiz azul","Синий карандаш"),("Puerta verde","Зелёная дверь"),("Mesa grande","Большой стол"),("Caja pequeña","Маленькая коробка")],["Начни с знакомых существительных: caja, lápiz, puerta.","Rojo/roja — один красный цвет; pequeño/pequeña — один размер.","Caja roja — красная коробка; mesa grande — большой стол."])
],['caja','lápiz','puerta','mesa'],"Одну выбранную подпись можно оставить у предмета станции.")
envelope(9,"Бумажный механизм","В макете Тео письмо застряло в коробке. Он предлагает сначала открыть крышку, затем достать письмо. Это бумажный пример; инструменты не нужны.",[
 dialogue("es_09_mechanism","Как помочь?","Abrir — открыть, sacar — достать. Выбери действия по порядку.",[("Тео","Крышка закрыта. Что поможет добраться до письма?",[("Abrir la caja.",True,"Крышка открыта; теперь письмо видно."),("Cerrar la caja.",False,"Cerrar закрывает. Сейчас нужна открытая коробка."),("Poner la caja en la mesa.",False,"Коробка уже на столе. Сначала открой крышку.")]),("Тео","Письмо видно. Что дальше?",[("Sacar la carta.",True,"Ты достала письмо. Ayudar — помочь."),("Cerrar la caja.",False,"Письмо пока внутри. Sacar означает достать.")])],["Подумай, что закрывает доступ к письму.","Сначала abrir, затем sacar. Poner — положить обратно.","«Abrir la caja» откроет крышку, «Sacar la carta» достанет письмо."])
],['carta','caja','mesa'],"Бумажная дверца снова работает. Тео оставляет рядом твою последовательность.")
envelope(10,"Любимая вещь","Нора хочет передать не каталог магазина, а историю твоей вещи. Старый предмет может быть любимым так же, как новый.",[
 compose("es_10_favorite","Карточка вещи","Выбери подпись или напиши свою. Mi — мой/моя; favorito — любимый; suave — мягкий.",[("book","Mi libro viejo favorito — моя любимая старая книга"),("pencil","Mi lápiz nuevo — мой новый карандаш"),("paper","Mi papel suave — моя мягкая бумага")],["Выбери знакомый предмет, не самый красивый.","Mi связывает подпись с тобой; nuevo и viejo описывают возраст вещи.","Можно выбрать «Mi libro viejo favorito» и добавить пару слов о своей книге."],[field("description","Что это за вещь и почему ты её выбрала?",False)])
],['libro','lápiz','papel'],"У станции есть твоя подпись предмета и вторая часть альбома.")
envelope(11,"Открытка с пятью видами","В конверте рисунок долины: река огибает камень, над ней гора, рядом дерево и условный водопад. Это рисунок, а не маршрут.",[
 match("es_11_valley","Подписать открытку","Разложи названия у словесных описаний пяти деталей.",[("Río","Вода течёт вдоль берега"),("Cascada","Вода падает уступом"),("Montaña","Высокая каменная вершина"),("Árbol","Ствол с кроной"),("Piedra","Отдельный камень у берега")],["Río и cascada оба про воду, но её движение разное.","Montaña — гора целиком; piedra — отдельный камень.","К подписи «вода падает уступом» подходит cascada."])
],['agua','azul','verde'],"На открытке появились пять названий. Она ещё не означает реальный выход.")
envelope(12,"Два придуманных места","Нора сравнивает два рисунка: на первом длинная река и высокая гора далеко, на втором короткий ручей и низкий столик. Помоги восстановить подпись первого.",[
 order("es_12_distance","Подпись панорамы","Собери фразу «Длинная река; высокая гора далеко». La/el — служебные слова перед названием.",["El río largo;","la montaña alta","está lejos."],["Фраза начинается с реки, потом переходит к горе.","Largo — длинный, alta — высокая, lejos — далеко. Corto и bajo описывают другой рисунок.","El río largo; → la montaña alta → está lejos."])
],['río','montaña'],"У вымышленной панорамы восстановлена подпись. Никаких советов о настоящей дороге она не даёт.")
envelope(13,"Линия воды","Хочется подписать свой рисунок. Нора предлагает слова luz, sombra, línea, color, dibujo — они помогают рассказать, что ты заметила.",[
 choose("es_13_caption","Подпись к рисунку","Для подписи «рисунок: синяя линия, свет» возьми dibujo, línea azul, luz.",[("drawing","Dibujo — рисунок"),("line","Línea azul — синяя линия"),("light","Luz — свет"),("shadow","Sombra — тень"),("color","Color verde — зелёный цвет")],["drawing","line","light"],["Начни с названия работы: dibujo.","В подписи есть линия и свет; тень сюда можно добавить в другой версии.","Выбери Dibujo, Línea azul и Luz."]),
 compose("es_13_my_caption","Мой вариант","Теперь выбери настроение своей подписи; учебную картинку можно заменить своим рисунком.",[("light","Luz en el río — свет на реке"),("shadow","Sombra del árbol — тень дерева"),("line","Una línea azul — синяя линия")],["Варианты равноценны.","Подпись может быть очень короткой.","Можно оставить «Una línea azul»."])
],['azul','río','árbol'],"В альбоме появилась подпись рисунка, выбранная тобой.")
envelope(14,"Погода внутри истории","Нора читает придуманный прогноз для открытки. На карточке явно написано: учебная история. Реальную погоду радио показывает отдельно.",[
 dialogue("es_14_weather","Когда идёт дождь?","Hoy — сегодня, mañana — завтра. Hay значит «есть/бывает».",[("Нора","Hoy hay sol. Mañana hay lluvia y viento. Что нарисовать в окошке «завтра»?",[("Lluvia y viento.",True,"Верно для этой вымышленной истории: дождь и ветер завтра."),("Sol.",False,"Солнце стоит после hoy — сегодня."),("Una montaña.",False,"Гора — место, а Нора сейчас говорит о погоде.")])],["Найди слово mañana.","Hoy и mañana разделяют две части сообщения.","После mañana стоят lluvia y viento — дождь и ветер."])
],['montaña','carta'],"В учебной открытке меняется маленькое окошко погоды. Это не прогноз для семейного выхода.")
envelope(15,"Моя заметка из долины","Теперь радио ждёт твою маленькую заметку: что здесь, а что там? Можно говорить о рисунке, не выдавая его за посещённое место.",[
 compose("es_15_dispatch","Заметка из долины","Aquí — здесь, allí — там. Выбери тему: она определит оформление финальной открытки.",[("valley","Aquí está mi dibujo del valle — здесь мой рисунок долины"),("sky","Allí hay una nube en el cielo — там облако в небе"),("river","Allí está el río — там река")],["Выбери одну деталь своей или учебной картинки.","Aquí указывает на близкое; allí — на то, что дальше на рисунке.","Можно выбрать «Aquí está mi dibujo del valle» и подписать открытку."],[field("broadcast_theme","Моя тема выпуска",False),field("dispatch","Моя заметка",False)])
],['dibujo','río','montaña'],"Твоя открытка готова к атласу как рисунок, без отметки о посещении.")
envelope(16,"Потерянный ключ","Нора прислала кадры маленького происшествия: пришла домой, искала ключ, нашла, взяла письмо и вернулась на станцию. Кадры перепутались.",[
 order("es_16_story","Пять кадров","Поставь кадры по описанной истории. Формы llega/busca связаны с карточками llegar/buscar.",["Nora llega a casa.","Nora busca la llave.","Nora encuentra la llave.","Nora lleva la carta.","Nora vuelve a la estación."],["Сначала Нора приходит; ключ нельзя найти раньше поиска.","Llegar → buscar → encontrar → llevar → volver.","Начни с «Nora llega a casa», затем «Nora busca la llave»."])
],['casa','llave','carta'],"В альбоме есть история из пяти кадров, а не пять разрозненных переводов.")
envelope(17,"Прогулка бумажного героя","Тео нарисовал комнату на клетчатой бумаге. Герой в центре, письмо справа, коробка за героем. Настоящую комнату обходить не нужно.",[
 match("es_17_directions","Где находится?","Подбери направление для предметов на словесной схеме.",[("Izquierda","Левая сторона"),("Derecha","Правая сторона, где письмо"),("Delante","Впереди, где стол"),("Detrás","Позади, где коробка")],["Представь, что смотришь в ту же сторону, что герой.","Delante и detrás описывают вперёд/назад, не влево/вправо.","Письмо справа: derecha. Коробка позади: detrás."]),
 dialogue("es_17_walk","Дойти до письма","Caminar — идти пешком. Выбери одно указание.",[("Тео","Письмо справа. Куда отправить героя?",[("Caminar a la derecha.",True,"Герой бумажной сцены дошёл до письма."),("Caminar a la izquierda.",False,"Это налево. Письмо находится справа — derecha.")])],["Письмо справа от старта.","A la derecha — направо.","Выбери «Caminar a la derecha»."])
],['carta','mesa','caja'],"Бумажный герой получил понятное указание.")
envelope(18,"Лишний камень в подписи","На картинке ровно два камня, но Нора подписала tres piedras. Она просит помочь заметить разницу.",[
 choose("es_18_correction","Исправить подпись","На рисунке: камень ● и камень ●. Выбери подпись, соответствующую двум камням.",[("one","Una piedra — один камень"),("two","Dos piedras — два камня"),("three","Tres piedras — три камня")],["two"],["Посчитай отмеченные камни: один, два.","Uno/una — один, dos — два, tres — три. В старой подписи на один больше: más.","Выбери «Dos piedras». Это на один меньше: menos."])
],['piedra','dibujo'],"Нора: «Я написала лишнее. Хорошо, что можно спокойно исправить подпись».")
envelope(19,"Конец маленькой истории","Герой дошёл до окна: видит реку, слышит дождь, чувствует ветер. Какую деталь оставить в конце рассказа, решаешь ты.",[
 match("es_19_senses","Что заметил герой?","Раздели три наблюдения. Это текстовая сцена: звук включать не нужно.",[("Veo el río.","Вижу реку"),("Oigo la lluvia.","Слышу дождь"),("Siento el viento.","Чувствую ветер")],["Глаголы различают способы заметить мир.","Ver/veo — видеть, oír/oigo — слышать, sentir/siento — чувствовать.","Oigo la lluvia значит «Слышу дождь»."]),
 dialogue("es_19_ending","Выбрать финал","Elegir — выбирать, contar — рассказывать. Обе концовки подходят известным фактам.",[("Нора","Что герой расскажет в конце?",[("Elijo contar: veo el río.",True,"Финал будет про реку, которую он увидел."),("Elijo contar: oigo la lluvia.",True,"Финал будет про дождь, который он услышал.")])],["Оба наблюдения присутствуют в истории.","Здесь нет единственной любимой автором концовки.","Выбери про реку или дождь; решение останется в альбоме."])
],['río','lluvia','viento'],"В рассказе осталась твоя выбранная последняя реплика.")
envelope(20,"Выпуск Южного Маяка","В архиве уже двадцать конвертов. Нора освобождает место в эфире: какие три сообщения из твоего альбома услышат гости?",[
 choose("es_20_broadcast","Мой выпуск","Выбери три страницы для выпуска. Voz — голос, mensaje — сообщение, historia — история; juntos — вместе.",[("greeting","Hola: первый контакт"),("menu","Моё меню"),("object","Любимая вещь"),("valley","Открытка долины"),("story","История у окна")],[],["Вспомни три страницы, которые хочется показать.","Здесь выбираешь ты: порядок вкусов не оценивается.","Можно взять первый контакт, открытку долины и историю у окна."],3,3),
 compose("es_20_cover","Обложка эфира","Выбери оформление выпуска и, если хочешь, название. Hasta mañana — до завтра; возвращаться именно завтра необязательно.",[("valley","Historia del valle — история долины"),("cafe","Juntos en el café — вместе в кафе"),("workshop","Un mensaje de mi estación — сообщение моей станции")],["Обложка может продолжить тему пятнадцатого письма.","Любую обложку можно позднее заменить без новой награды.","Выбери один вариант и оставь короткое название."],[field("title","Название моего выпуска",False)])
],['hola','café','valle','mi'],"Полный альбом эфира собран. Осталось спокойно применить слова в смешанной проверке вместе.")

GRANTS={}
RECIPES={}
def recipe(key,title,kind,presentations):
    RECIPES[key]=dict(recipe_id=key,title=title,work_kind=kind,presentations=presentations)
def grant(key,title): GRANTS[key]=dict(grant_id=key,title=title,kind="known_presentation")
def stage(key,title,summary,prereqs,policy,budget,grant_ids,recipe_id,ids,criteria,next_hint,atlas=None,**extra):
    return dict(stage_id=key,title=title,summary=summary,prerequisite_stage_ids=prereqs,completion_policy=policy,budget_share=budget,grant_ids=grant_ids,atlas_unlock_ids=atlas or [],work_recipe_id=recipe_id,interaction_ids=ids,criteria=criteria,next_hint=next_hint,required=True,**extra)
def quest(qid,title,summary,skill,budget,anchor,location,stages,interactions,**extra):
    used_recipes={s['work_recipe_id'] for s in stages}
    used_grants={g for s in stages for g in s['grant_ids']}
    return dict(schema_version=2,quest_id=qid,revision=2,content_status="DRAFT",kind="project",title=title,story_title=title,summary=summary,is_main_quest=True,chapter_id="chapter_02",chapter_key="station_on_air",location_id=location,entry_anchor_id=anchor,goal_group="maya_first_goals",goal_order={"FG01":1,"FG11":11,"FG08":8}.get(qid,99),estimated_minutes={"min":5,"max":240},completion_criteria=[c for s in stages for c in s['criteria']],variants=[dict(id="home",title="Дом и семейные шаги",home_available=True)],context=dict(adult_presence="for_review",requires_purchase=False,requires_network=False,risk_tags=[]),evidence_policy=dict(allowed=["game_event","parent_observation","note","local_image"],required_media=False,reviewer="parent"),reward_policy=dict(activity_budget=budget,lane="project",skill_weights_percent={skill:100},world_effect_ids=[]),repeat_policy=dict(mode="once",max_completions=1),provenance=dict(origin="sur_first_chapter"),required_capabilities=["adventure_v1","exhibits_v1"],content_dependencies=[],exhibit_ids=sorted(used_recipes),adventure=dict(stages=stages,interactions=interactions,work_recipes={k:RECIPES[k] for k in sorted(used_recipes)},grant_definitions={k:GRANTS[k] for k in sorted(used_grants)},dialogues={},return_text="Уже сделанное осталось в архиве. Можно продолжить следующий маленький шаг или посмотреть свои работы.",**extra))

for key,title,kind in [("radio_contact_card","Первый контакт","note"),("radio_menu","Моё меню","album"),("station_word_label","Подпись предмета","note"),("valley_postcard","Моя долина","image"),("radio_album","Альбом эфира","album"),("radio_episode_card","Карточка выпуска","album")]: recipe(key,title,kind,["frame","album"]); grant({"radio_contact_card":"radio_first_contact","radio_episode_card":"radio_callsign"}.get(key,key),title)
es_stages=[stage("es_intro","Первый ответ","Нора запишет позывной после первого осмысленного ответа.",[],"automatic",0,["radio_first_contact"],"radio_contact_card",E[0]['interaction_ids'],["Применены пять слов первого письма; выбран ответ и карточка позывного."],"Можно открыть второе письмо или посмотреть первую открытку.")]
for n in range(1,5):
    envs=E[(n-1)*5:n*5]
    ids=[k for e in envs for k in e['interaction_ids'] if n!=1 or e['number']!=1]
    r=["radio_menu","station_word_label","valley_postcard","radio_album"][n-1]
    es_stages.append(stage(f"es_channel_{n:02}",CHANNELS[n-1],f"Пять коротких ситуаций канала «{CHANNELS[n-1]}».",["es_intro" if n==1 else f"es_channel_{n-1:02}"],"automatic",8,[r],r,ids,[f"В личном наборе {n*25} разных лексем.",f"Завершены смысловые сцены конвертов {(n-1)*5+1}–{n*5}."],"Можно открыть альбом или следующее письмо.",envelope_ids=[e['envelope_id'] for e in envs],required_lexeme_count=n*25))
sample_indices=[0,6,11,17,23,26,32,37,42,48,50,56,61,68,74,76,82,87,91,98]
sample=[lexemes[i] for i in sample_indices]
final_check=match("es_mixed_check","Смешанный эфир","Двадцать слов из всех четырёх каналов. Цель этой версии — 14 узнаваний или применений без открытия карточки. Помощь разрешена; она отмечается у конкретной попытки.",[(x['base_form'],x['translation']) for x in sample],["Можно сделать паузу и вернуться к письмам.","Вспомни сцену, где встречалось слово: заказ, предмет, пейзаж или история.","Открытая карточка помогает продолжить, но это слово в этой попытке не считается ответом без помощи."])
final_check['config'].update(lexeme_ids=[x['lexeme_id'] for x in sample],minimum_unassisted_correct=14,selection_policy="balanced_fixed_sample",replay_awards=False)
add(final_check)
add(real("es_joint_broadcast","Завершить передачу вместе","Посмотрите смешанную попытку и выбранный выпуск. Открытие карточек само по себе не означает знание слов.",["В наборе 100 разных лексем.","Собран собственный выпуск.","Есть не менее 14 ответов без помощи из 20 в одной сохранённой смешанной попытке."],[field("review_note","Что получилось применить?"),field("authorship","Что выбрала Майя?",False)],[],["Откройте альбом и результат последней попытки.","Если пока меньше 14, предметы каналов остаются; можно выбрать несколько писем для повторения.","Вместе отметьте конкретный результат. Порог меняется только в новой согласованной ревизии."]))
es_stages.append(stage("es_final","Выпуск в эфире","Нора ждёт выбранные страницы и спокойную смешанную попытку.",["es_channel_04"],"joint_review",8,["radio_callsign"],"radio_episode_card",["es_mixed_check","es_joint_broadcast"],["100 уникальных лексем; собственный выпуск; 14 из 20 ответов без карточки в смешанной проверке."],"Можно выставить альбом или открыть старые письма без повторной награды."))
es=quest("FG01","Голоса Южного Маяка","Помочь Норе собрать передачу и личный альбом из ста полезных испанских слов.","spanish",40,"radio","radio_cafe",es_stages,I,lexicon=lexemes,envelopes=E,channels=[dict(channel_id=f"es_channel_{n+1:02}",title=t,lexeme_ids=[x['lexeme_id'] for x in lexemes[n*25:n*25+25]]) for n,t in enumerate(CHANNELS)],final_check=dict(interaction_id="es_mixed_check",sample_size=20,minimum_unassisted_correct=14,per_channel=5),grammar_support=[dict(text=t,translation=g) for t,g in [("el / la / un / una","служебные слова перед названием"),("y","и"),("en","в / на"),("de / del","из / принадлежность"),("es / está","есть / находится"),("hay","есть, имеется"),("¿Puedes…?","Можешь…?"),("para","для"),("soy / eres","я / ты есть"),("a","к / в направлении")]],choice_effects={"broadcast_theme":{"valley":"valley_postcard","sky":"radio_album","river":"valley_postcard"}})
es['adventure']['dialogues']={"first_success":"Теперь я знаю, как зовётся твоя станция. Оставлю это имя в журнале эфира.","after_hint":"Вот недостающий кусочек. Попробуем собрать сообщение ещё раз.","return":"У нас осталось письмо про мастерскую. Можно продолжить его или открыть альбом.","pause":"Письма останутся на столе. Можно закончить сегодня.","final":"У передачи теперь есть твои выбранные сообщения. Позывной и альбом остаются на станции."}
for cosmetic_id in ["es_callsign", "es_20_cover"]:
    es['adventure']['interactions'][cosmetic_id]['config']['lexeme_credit'] = False
es['goal_order'] = 1
es['editorial_priority'] = 1
write("quests/FG01.json",es)

# The workshop supplies a runnable foundation, not a completed child's work.
I={}
for k,t,kind in [("game_concept_card","Замысел игры","note"),("game_project_version","Версия моей игры","game"),("game_premiere","Премьера игры","game")]: recipe(k,t,kind,["terminal","frame"])
for k,t in [("game_concept_card","Замысел на верстаке"),("arcade_movement","Герой на экране"),("arcade_counter","Счётчик огоньков"),("arcade_victory_lamp","Лампа победы"),("arcade_restart_button","Кнопка перезапуска"),("arcade_premiere","Автомат с игрой")]: grant(k,t)
concept=add(compose("game_choose_concept","Чего хочет герой?","Тео нашёл пустой корпус автомата. Выбери героя и цель; основа умеет собирать три предмета.",[("lights","Хранитель собирает огоньки"),("postcards","Почтальон собирает открытки"),("stones","Исследователь собирает камни")],["Герою достаточно одной понятной цели.","Все темы используют один цикл: двигаться, собрать три предмета, победить, начать снова.","Можно выбрать хранителя и три огонька; собственный рисунок добавишь позже."],[field("hero","Кто герой?"),field("goal","Что он хочет собрать?")]))
predict=add(dialogue("game_speed_prediction","Две дорожки Тео","В макете один герой проходит за секунду 100 клеточных единиц, второй — 200. Сначала предположи, потом проверь в своей основе.",[("Тео","Если увеличить скорость с 100 до 200 при той же длительности, что изменится?",[("Герой пройдёт примерно вдвое дальше.",True,"Теперь проверь это в отдельном проекте: клавишу держим одинаковое время."),("Огоньков станет вдвое больше.",False,"Скорость меняет движение; количество огоньков задаётся отдельно."),("Не знаю, хочу сравнить вместе.",True,"Помощь разрешена. Сравните две скорости и запишите наблюдение.")])],["Сравниваем путь за одинаковое время.","Скорость отвечает за расстояние за секунду, а не за предметы.","При 200 вместо 100 герой за то же время идёт примерно вдвое дальше."]))
layout=add(choose("game_choose_layout","Три места для света","Выбери три позиции для своей схемы; в реальном проекте проверь, что к ним можно подойти.",[("upper_left","Сверху слева"),("upper_right","Сверху справа"),("lower_left","Снизу слева"),("lower_right","Снизу справа"),("center","В центре")],[],["У каждого огонька должно быть своё место.","Можно расположить их треугольником или дорожкой.","Например: сверху слева, сверху справа, снизу справа."],3,3))
win_logic=add(order("game_win_sequence","Когда загорается лампа?","Собери порядок проверки победы. До третьего огонька финал не показываем.",["Герой касается ещё не собранного огонька.","Огонёк исчезает; счётчик увеличивается один раз.","Если собраны все три, появляется сообщение победы."],["Сначала должно произойти касание.","Проверка общего количества идёт после обновления счётчика.","Касание → исчезновение и +1 → проверка трёх огоньков."]))
bug=add(match("game_stubborn_counter","Упрямый счётчик — отдельный пример","Этот пример не меняет твою игру. После одного касания видим 2/3: сопоставь наблюдение и объяснение.",[("Одно касание, счётчик +2","Один предмет посчитан дважды"),("Собранный огонёк остаётся доступным","Следующее касание может повторно увеличить счётчик"),("После перезапуска осталось 2/3","Счётчик не сброшен")],["Сравни число событий и изменение числа.","Каждый огонёк должен перейти в состояние «собран» один раз.","Одно касание и +2 означает двойной учёт. Проверь защиту уже собранного предмета."]))
steps=[
 ("game_move","Движение","0.1",["Основа запущена отдельным проектом.","Майя предсказала и проверила одно изменение скорости или направления."],[field("prediction","Что ты ожидала изменить?"),field("observation","Что произошло после изменения?"),field("own_change","Что выбрала или изменила Майя?")],"Измени speed в настройках учебной игры вместе; сравни одинаковое нажатие при двух значениях.","arcade_movement",[predict]),
 ("game_goal","Три огонька","0.2",["В проекте размещены три собираемых объекта.","Каждый исчезает при касании и увеличивает счётчик ровно один раз."],[field("layout","Как расположены три предмета?"),field("observation","Как проверили исчезновение и счётчик?")],"Перенеси выбранную схему в отдельный проект. Собери предмет и вернись на его место: счётчик не должен измениться второй раз.","arcade_counter",[layout]),
 ("game_win","Понятная победа","0.3",["После одного и двух предметов победы нет.","После третьего появляется выбранное сообщение."],[field("win_message","Какое сообщение ты выбрала?"),field("observation","Что происходит после 1, 2 и 3 предметов?")],"Выбери текст победы. Проверь три промежуточных значения; готовый финал не должен включаться раньше.","arcade_victory_lamp",[win_logic]),
 ("game_restart","Снова с начала","0.4",["После перезапуска счётчик равен нулю.","Герой и все три предмета вернулись на свои стартовые места.","Повторный цикл снова проходим."],[field("observation","Что сбросилось после кнопки и клавиши R?")],"Собери свет, нажми «Ещё раз» и проверь ноль, старт героя, три предмета и повторную победу.","arcade_restart_button",[]),
 ("game_premiere","Вечер первого запуска","1.0",["Взрослый прошёл игру от запуска до победы и перезапуска.","Есть одно наблюдение зрителя и выбранное Майей улучшение.","После улучшения полный цикл проверен снова.","Сохранены исходники, авторство и зарегистрированная версия."],[field("viewer_observation","Что заметил первый игрок?"),field("own_change","Какое улучшение ты выбрала и внесла?"),field("causal_explanation","Почему изменение помогло?"),field("shared_work","Что сделали вместе?"),field("source_version","Какая сохранённая версия проекта?")],"Пригласи взрослого сыграть; выбери одно улучшение. Взрослый сохраняет копию исходников и регистрирует конкретную сборку отдельно.","arcade_premiere",[bug])]
game_stages=[stage("game_concept","Замысел автомата","Пустой экран ждёт твоего героя и цели.",[],"self_attest",0,["game_concept_card"],"game_concept_card",[concept],["Выбран герой и понятная цель."],"Можно нарисовать обложку или открыть учебную основу вместе.")]
for n,(key,title,version,criteria,fields,prompt,g,ids) in enumerate(steps):
    fields=fields+[field("own_contribution","Какое решение или изменение сделала Майя на этом шаге?")]
    ids=ids+[add(real(key+"_return",title+" — проверить вместе",prompt,criteria,fields,["Семейный компьютер","Godot и учебная основа","Помощь взрослого"],["Откройте соответствующую сохранённую версию проекта.","Проверьте конкретный критерий в работающей игре; одного нажатия «Запустить» недостаточно.","Коротко запишите наблюдение и собственную правку; если есть ошибка, предыдущая версия останется."],starter_project_id="station_arcade_starter",learning_version=version,requires_own_change=True,demonstration_is_completion=False,required_checks=["launches","movement","collection","win","clean_restart","own_improvement"] if key=="game_premiere" else []))]
    game_stages.append(stage(key,title,prompt,[game_stages[-1]['stage_id']],"joint_review",12,[g],"game_premiere" if key=="game_premiere" else "game_project_version",ids,criteria,"Можно сохранить текущую версию и закончить сегодня.",version_label=version))
game=quest("FG11","Автомат для станции","Создать маленькую законченную игру и оставить её исходники и историю версий в личном архиве.","programming",60,"workbench","workshop_annex",game_stages,I,starter_project_id="station_arcade_starter",authorship_template=dict(prepared_foundation="Учебная основа SUR, подготовлена разработчиком.",child_choices="Заполняется по фактическим решениям Майи.",shared_work="Заполняется по тому, что сделали вместе.",demonstration_only=True),choice_effects=dict(theme={"lights":"game_concept_card","postcards":"game_concept_card","stones":"game_concept_card"},layout={"upper_left":"arcade_counter","upper_right":"arcade_counter","lower_left":"arcade_counter","lower_right":"arcade_counter","center":"arcade_counter"}),choice_instructions=dict(theme="Выбранная тема становится названием героя и предметов в собственной копии игры.",layout="Выбранные три места перенести в координаты огоньков учебного проекта; проверить достижимость вместе."))
game['adventure']['dialogues']={"intro":"Тео: «У меня есть корпус автомата. Какого героя ты поселишь на экране?»","return":"Твоя версия осталась на верстаке. Можно показать её или продолжить одну правку.","bug":"Здесь отдельный пример с двойным счётом. Твоя рабочая игра не менялась.","final":"На станции появилась игра. В карточке записано, какие решения её автор выбрала сама и что мы сделали вместе."}
game['goal_order'] = 2
game['editorial_priority'] = 2
write("quests/FG11.json",game)

I={}
for k,t,kind in [("water_question_card","Мой вопрос о воде","note"),("field_plan","Полевая страница","note"),("water_observation_page","Наблюдение воды","observation"),("water_comparison","Сравнение двух записей","observation"),("water_diptych","Два голоса воды","diptych"),("home_water_study","Исследование по материалам","observation")]: recipe(k,t,kind,["frame","table","album"])
for k,t in [("water_question_card","Вопрос на карте"),("field_album","Полевой альбом"),("river_diagram_panel","Речная половина диорамы"),("fall_diagram_panel","Водопадная половина диорамы"),("water_compare_switch","Переключатель сравнения"),("water_diptych","Диптих наблюдений")]: grant(k,t)
intro=add(inspect("water_old_note","Старая карточка","В архиве записано: «Вода всегда звучит одинаково?» Открой обе половины заметки.",[("claim","Первое предположение","Мне казалось, что у воды один голос. Но я записал только один день."),("invitation","Поле для другого ответа","Если твой ответ отличается от моего, оставь оба. Архив растёт, когда кто-то замечает своё.")],["На карточке есть вопрос, а не готовый вывод.","Одной записи может не хватать, чтобы сравнивать.","Открой обе половины и выбери собственный вопрос."]))
question=add(compose("water_question","Что исследовать?","Твой вопрос изменит подсказки сравнения. Его можно уточнить позже.",[("movement","Как движется вода?"),("sound","Чем отличаются её голоса?"),("lines","Какие линии и цвета замечаешь?"),("own","Свой вопрос")],["Можно выбрать то, что хочется заметить.","Для вопроса о звуке запись аудио не нужна: достаточно слов.","Например: «Как вода огибает камни?»"],[field("question","Мой вопрос",False)]))
practice=add(match("water_home_examples","Две учебные картинки","Здесь условные примеры: они не засчитывают семейный выход и не открывают атлас.",[("Линии идут вдоль берега","Рисунок горизонтального течения"),("Линии падают с уступа","Рисунок падающей воды"),("Пустая строка под рисунками","Место для своего наблюдения")],["Следи за направлением линий, не за красотой картинки.","Один рисунок показывает течение вдоль, другой — падение сверху.","Линии вдоль берега соедини с горизонтальным течением."]))
plan=add(real("water_family_plan","Подготовить полевую страницу","Взрослые выбирают места и день вне сюжета. В исходном варианте речная страница относится к Río Azul, водопадная — к выбранному водопаду из ближнего каталога.",["Семья выбрала реальный вариант обоих наблюдений.","Понятно, чем сделать запись.","Речная точка действительно соответствует выбранной записи атласа."],[field("family_plan","Какие два наблюдения мы планируем?"),field("recording_method","Блокнот, рисунок или совместная запись?"),field("atlas_choice","Подтверждённая речная точка: Río Azul или заранее изменённый вариант?")],["Бумага и карандаш или запись после возвращения","Сопровождение взрослого"],["Не требуется выбирать день немедленно.","В полевой странице три подсказки, но достаточно одной короткой записи.","Можно переписать: «Что заметила / На что похоже / Что хочется сравнить»."],field_page=["Что заметила","На что похоже","Что хочется сравнить"],real_visit_required=True))
water_stages=[stage("water_intro","Вопрос старого архива","Два пустых окна ждут твоего вопроса.",[],"automatic",0,["water_question_card"],"water_question_card",[intro,question],["Выбран или сформулирован исследовательский вопрос."],"Можно поиграть с учебными картинками и подготовить страницу."),stage("water_plan","Полевая страница","Согласовать семейный вариант наблюдений и способ записи.",["water_intro"],"joint_review",0,["field_album"],"field_plan",[practice,plan],["Семья выбрала реальный вариант; подготовлен способ записи."],"Реку и водопад можно наблюдать в любом порядке и в разные дни.")]
for key,title,atlas,grant_id in [("water_river","Первый голос: река","rio_azul","river_diagram_panel"),("water_fall","Второй голос: водопад","waterfalls","fall_diagram_panel")]:
    value=real(key+"_return",title,"Принеси наблюдение с состоявшегося семейного выхода. Можно написать, нарисовать или вместе записать устный рассказ; файл и координаты не нужны.",["Взрослый подтверждает состоявшийся семейный выход в выбранную точку.","Сохранено отдельное наблюдение Майи для этой страницы."],[field("observation","Что заметила?"),field("family_visit","Совместная отметка состоявшегося выхода"),field("analogy","На что похоже?",False),field("compare_later","Что хочется сравнить?",False)],["Собственное наблюдение","Совместное подтверждение"],["Одной конкретной детали достаточно.","Можно говорить о движении, звуке, линиях, цвете или окружении.","Пример формы записи: «Я заметила…, это напомнило…». Содержание берётся из твоего наблюдения."],real_visit_required=True,atlas_location_id=atlas,home_materials_are_visit=False)
    iid=add(value)
    water_stages.append(stage(key,title,"Эта страница появляется после реального наблюдения.",["water_plan"],"joint_review",10,[grant_id],"water_observation_page",[iid],["Состоялся выбранный семейный выход.","Сохранено своё наблюдение для соответствующей страницы."],"Можно оформить страницу или подготовить второе наблюдение.",atlas=[atlas],real_visit_required=True))
compare=add(interaction("water_compare_pages","compare_observations","Две страницы рядом","Сравни собственные записи. Пример «вдоль берега / сверху вниз» подходит не всем местам; свой ответ важнее совпадения с ним.",["Открой обе свои страницы и выбери один признак.","Укажи, что именно было у реки и что у водопада.","Можно написать: «В первой записи я заметила …, а во второй …»."],dict(source_stage_ids=["water_river","water_fall"],categories=[item(k,t) for k,t in [("movement","Движение"),("sound","Звук"),("lines","Цвет и линии"),("surroundings","Окружение"),("own","Свой признак")]],min_observations=2,fields=[field("difference","Одно конкретное различие по моим наблюдениям")],question_hints={"movement":"Сравни направление и непрерывность движения.","sound":"Вспомни слова, которыми описала каждый голос воды.","lines":"Сравни замеченные линии и цвета.","own":"Вернись к своему вопросу; обе записи могут сохранить разные ответы."})))
water_stages.append(stage("water_compare","Мой ответ архиву","Два наблюдения можно сравнить по выбранному вопросу.",["water_river","water_fall"],"joint_review",10,["water_compare_switch"],"water_comparison",[compare],["Есть конкретное различие, связанное с двумя собственными наблюдениями."],"Можно оставить оба ответа — старый и свой — рядом."))
exhibit=add(compose("water_make_diptych","Название находки","Объедини две страницы и сравнение. Художественный звук диорамы — ресурс игры, а не твоя запись места.",[("wall","Диптих для стены"),("table","Диорама для стола"),("album","Альбом двух наблюдений")],["Одна работа может иметь разные способы показа.","Обе страницы и сравнение останутся внутри любого оформления.","Можно выбрать альбом и назвать его «Два голоса воды»."],[field("title","Название моего исследования")],["water_river","water_fall","water_compare"]))
water_stages.append(stage("water_exhibit","Два голоса в архиве","Две страницы и твой ответ становятся одной личной работой.",["water_compare"],"self_attest",10,["water_diptych"],"water_diptych",[exhibit],["Две страницы и сравнение объединены; выбрано оформление и название."],"Можно поставить диптих на выставку или оставить в архиве."))
water=quest("FG08","Два голоса воды","Сохранить два семейных наблюдения, сравнить их и оживить диораму своим ответом.","outdoors",40,"station_map","field_archive",water_stages,I,home_branch=dict(title="Исследование по материалам",interaction_ids=[practice],work_recipe_id="home_water_study",completes_original_quest=False,atlas_unlock_ids=[],budget_share=0),choice_effects=dict(question={"movement":"water_question_card","sound":"water_question_card","lines":"water_question_card","own":"water_question_card"}),choice_instructions=dict(question="Выбор вопроса определяет question_hints сравнения и предлагаемый признак; свой вопрос разрешён."))
water['adventure']['work_recipes']['home_water_study']=RECIPES['home_water_study']
water['adventure']['dialogues']={"return":"Продолжим, когда выберем день. Уже принесённые страницы остались в альбоме.","observation_saved":"В альбоме сохранена твоя запись. Можно дать ей название и выбрать место в диораме.","final":"Если твой ответ отличается от моего, оставь оба. Архив растёт, когда кто-то замечает своё.","audio_label":"Художественный звук из ресурсов игры; не запись конкретного места."}
water['goal_order'] = 3
water['editorial_priority'] = 3
write("quests/FG08.json",water)

recipe("silhouette_sheet","Три силуэта","image",["frame","table"])
recipe("silhouette_frame","Силуэт для вывески","image",["frame"])
grant("silhouette_frame","Рамка новой вывески")
I={}
samples=add(inspect("silhouette_samples","Что видно издалека?","Тео предлагает выбрать силуэт для новой вывески. Осмотри три словесных образца.",[("round","Круглая чашка","Один крупный контур, ручка видна сбоку."),("tall","Высокая чашка","Узкий вытянутый контур, ручка около середины."),("wide","Широкая чашка","Низкий контур, большая ручка и широкое основание.")],["Силуэт показывает внешний край.","Менять можно пропорции и положение ручки.","Сравни высокую и широкую чашку: форма различается даже без деталей."]))
draw=add(real("silhouette_draw","Три собственных варианта","Нарисуй один выбранный предмет тремя разными силуэтами. Достаточно бумаги и карандаша; художественный вкус не оценивается.",["Есть три различающихся силуэта одного предмета."],[field("variants_note","Чем отличаются три варианта?")],["Бумага","Карандаш"],["Выбери простой знакомый предмет.","В одном варианте измени высоту, в другом — ширину или наклон.","Например: три чашки — высокая, широкая и с большой ручкой."]))
pick=add(compose("silhouette_pick","Вывеска, которую узнают","Выбери один свой вариант и объясни выбор одной фразой.",[("first","Первый силуэт"),("second","Второй силуэт"),("third","Третий силуэт")],["Покажи три собственных варианта рядом.","Подумай, какой легче узнать издалека.","Можно написать: «У этого хорошо видна ручка»."],[field("reason","Почему этот вариант?")]))
ar_stages=[stage("silhouette_inspect","Образцы на верстаке","Осмотреть три примера.",[],"automatic",0,[],"silhouette_sheet",[samples],["Открыты три образца."],"Можно сделать свои три формы."),stage("silhouette_make","Мои три формы","Сделать три варианта.",["silhouette_inspect"],"joint_review",10,[],"silhouette_sheet",[draw],["Есть три разных силуэта одного предмета."],"Можно выбрать любимый вариант."),stage("silhouette_exhibit","Новая вывеска","Выбрать и объяснить один вариант.",["silhouette_make"],"self_attest",10,["silhouette_frame"],"silhouette_frame",[pick],["Один вариант выбран; есть короткое объяснение."],"Рамка готова к выставке.")]
ar=quest("AR02","Три силуэта для новой вывески","Сделать три формы одного предмета и выбрать понятный силуэт для вывески.","drawing",20,"workbench","workshop_annex",ar_stages,I)
ar.update(revision=1,is_main_quest=False)
ar.pop('goal_group'); ar.pop('goal_order')
write("examples/three_silhouettes.schema2.json",dict(schema_version=2,package_type="sur_quest_pack",package_id="sur_family_three_silhouettes",required_capabilities=["adventure_v1","exhibits_v1"],quests=[ar]))

secret_specs=[("postcard_back","station","station_postcard","Оборот открытки","На обороте открытки видна крошечная подпись. Переверни её.","Письмо может идти долго. Имя отправителя дождётся своего читателя."),("brass_stars","station","station_brass_card","Созвездие в латуни","Поднеси карточку к нарисованной лампе: отверстия складываются в узор.","Три отверстия образуют маленький треугольник — карту света для старой станции."),("frame_initial","gallery","gallery_frame","Буквы внутри рамы","У пустой рамы есть надпись на внутренней стороне.","Здесь можно оставить незаконченное. Продолжение найдёт место позже."),("gallery_echo","gallery","gallery_bench","Тихое эхо","На скамье лежит карточка с двумя линиями. Открой её подпись.","Галерея умеет быть тихой. Посетителей можно пригласить, а можно посмотреть всё самой."),("radio_reply","object_ui","radio","Ответный ритм","На шкале радио отмечены короткая, короткая и длинная черты.","Ответ станции: точка, точка, длинный свет. Этот ритм виден и при выключенном звуке."),("atlas_margin","object_ui","station_map","Пометка на полях","У края учебной карты торчит бумажный язычок.","Карта хранит историю наблюдений. Настоящую дорогу семья выбирает отдельно.")]
secrets=[]
for key,place,anchor,title,prompt,reveal in secret_specs:
    secrets.append(dict(secret_id=key,location_group=place,entry_anchor_id=anchor,title=title,optional=True,prerequisite_stage_ids=[],budget_share=0,work_recipe_id="story_find",interaction=inspect("secret_"+key,title,prompt,[("reveal",title,reveal)],["Посмотри на необычную деталь предмета.","Её можно открыть один раз без таймера и повторных щелчков.","Открой подпись детали: находка сохранится в истории."])))
finale=compose("chapter_choose_exhibits","Вечер открытой станции","Выбери название выставки и способ провести вечер. Запись эфира, игра и водный диптих остаются твоими работами; существующие места не заменяются автоматически.",[("quiet","Тихая выставка"),("guests","Открытки гостей")],["Нужны результаты трёх завершённых приключений.","Выбор тихого вечера даёт ту же памятную карточку.","Можно выбрать «Тихая выставка», назвать её и оставить работы в альбоме."],[field("exhibition_title","Название вечера"),field("radio_work_id","Выбранная работа эфира"),field("game_work_id","Выбранная версия игры"),field("water_work_id","Выбранный водный диптих")])
chapter=dict(schema_version=2,chapter_key="station_on_air",title="Станция на связи",required_quest_ids=["FG01","FG11","FG08"],entry_prerequisite="S00",intro=["Пробуждение станции заметили жители долины. На столе три незавершённые записи.","Нора прислала конверт. Тео оставил чертёж. В полевом архиве ждёт вопрос о воде.","Любую линию можно начать первой; остальные дождутся возвращения."],secrets=secrets,secret_reward=dict(minimum_unique_finds=3,grant_id="secret_constellation_theme",budget_share=0),finale=dict(finale_id="open_station_evening",required_completed_quest_ids=["FG01","FG11","FG08"],budget_share=0,grant_ids=["gallery_evening_light","chapter_card"],work_recipe_id="chapter_album",interaction=finale,reactions=[dict(speaker="Нора",text="В твоём альбоме есть выбранный позывной и сообщения. Можно открыть любимую страницу."),dict(speaker="Тео",text="У твоей игры есть сохранённая версия. Можно пригласить взрослого сыграть."),dict(speaker="Архив",text="Старый вопрос и твои наблюдения теперь стоят рядом. Здесь осталось место для следующей истории.")],skip_animation_preserves_result=True,replay_budget_share=0),next_postcard="В следующем письме — одна новая тема. Сначала можно побыть среди своих работ.")
write("chapters/station_on_air.json",chapter)
write("dialogues/station_on_air.json",{q['quest_id']:q['adventure']['dialogues'] for q in [es,game,water]})
write("exhibits/first_chapter_recipes.json",dict(schema_version=2,recipes=RECIPES,grants=GRANTS))
print(f"Built {len(lexemes)} unique lexemes, {len(E)} envelopes, 3 adventures, 6 secrets and one example package.")
