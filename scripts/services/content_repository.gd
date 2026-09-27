class_name ContentRepository
extends RefCounted

## Встроенный офлайн-каталог SUR. Карточки Phase B и выбранная часть банка
## Phase C начинают жизнь как DRAFT и становятся видимыми игроку только после
## отдельного родительского решения.

const SKILLS: Dictionary = {
	"spanish": {"title": "Испанский", "icon": "💬"},
	"drawing": {"title": "Рисование", "icon": "✎"},
	"music": {"title": "Пианино и музыка", "icon": "♫"},
	"wood": {"title": "Работа с деревом", "icon": "🪵"},
	"outdoors": {"title": "Походы и наблюдение", "icon": "⌁"},
	"rollers": {"title": "Ролики", "icon": "◉"},
	"math": {"title": "Математика", "icon": "∑"},
	"programming": {"title": "Программирование", "icon": "⌘"}
}

const SUBSKILLS: Dictionary = {
	"spanish": ["приветствие и вежливость", "переспрос", "короткие бытовые фразы"],
	"drawing": ["наблюдение", "композиция", "визуальный знак"],
	"music": ["ритм", "короткая мелодия", "повторение по слуху"],
	"wood": ["измерение", "планирование", "совместный безопасный проект"],
	"outdoors": ["наблюдение", "подготовка", "семейное планирование"],
	"rollers": ["стойка и баланс", "торможение", "повороты и контроль"],
	"math": ["измерение", "пропорции", "последовательности"],
	"programming": ["параметры", "предсказание результата", "версия и откат"]
}

const WORLD_EFFECT_IDS: Array[String] = [
	"atlas_first_page",
	"radio_channel_01_unlocked",
	"workbench_blueprint",
	"station_emblem_art",
	"station_motif",
	"author_artifact_card",
	"expedition_pack",
	"wind_parameter_saved",
	"display_room_sign",
	"observatory_view_01",
	"author_patch_accepted"
]

const PHASE_C_LOCATIONS: Array[Dictionary] = [
	{
		"location_id": "radio_cafe",
		"chapter_id": "chapter_02",
		"title": "Радиокафе «Южный Маяк»",
		"subtitle": "слова, вывески и короткие истории",
		"description": "Небольшая комнатка при радиорубке: доска меню, старые карточки эфира и место для собственных испанских реплик.",
		"symbol": "☕"
	},
	{
		"location_id": "workshop_annex",
		"chapter_id": "chapter_03",
		"title": "Пристройка мастерской",
		"subtitle": "эскизы, измерения и безопасные проекты",
		"description": "Светлая пристройка с чертёжным столом и каталогом семейных проектов. Реальные инструменты остаются под решением взрослого.",
		"symbol": "⌁"
	},
	{
		"location_id": "field_archive",
		"chapter_id": "chapter_04",
		"title": "Полевой архив",
		"subtitle": "наблюдения, карты и страницы экспедиций",
		"description": "Стеллаж с картами и полевыми заметками. Здесь домашние наблюдения и семейные прогулки превращаются в страницы личного атласа.",
		"symbol": "△"
	}
]

# Phase C сознательно берёт только часть банка 56: по три заготовки на каждое
# из восьми направлений. Полный банк остаётся в design brief и может добавляться пакетами.
const PHASE_C_SEEDS: Array[Dictionary] = [
	{"id":"ES01", "title":"Меню радиокафе", "summary":"Составить меню из пяти знакомых испанских слов и объяснить одно блюдо.", "skill":"spanish", "chapter":"chapter_02", "location":"radio_cafe", "kind":"project", "budget":20},
	{"id":"ES04", "title":"Уточни, а не угадай", "summary":"Потренироваться просить говорить медленнее и задавать уточняющий вопрос в короткой домашней сценке.", "skill":"spanish", "chapter":"chapter_02", "location":"radio_cafe", "kind":"practice", "budget":10},
	{"id":"ES05", "title":"Комикс без длинных слов", "summary":"Сделать четыре панели с очень короткими испанскими репликами; словарь разрешён.", "skill":"spanish", "chapter":"chapter_02", "location":"radio_cafe", "kind":"project", "budget":20},
	{"id":"AR01", "title":"Три силуэта", "summary":"Нарисовать один предмет тремя разными силуэтами и выбрать вариант для игровой иконки.", "skill":"drawing", "chapter":"chapter_02", "location":"radio_cafe", "kind":"project", "budget":20},
	{"id":"AR04", "title":"Персонаж по собственным правилам", "summary":"Придумать форму, характер и одну реплику вымышленного персонажа.", "skill":"drawing", "chapter":"chapter_02", "location":"radio_cafe", "kind":"project", "budget":20},
	{"id":"AR07", "title":"Исправление, которое нравится", "summary":"Вернуться к своей работе и осознанно изменить один выбранный элемент, сохранив обе версии.", "skill":"drawing", "chapter":"chapter_03", "location":"workshop_annex", "kind":"practice", "budget":10},
	{"id":"MU01", "title":"Ритмический пароль", "summary":"Повторить выбранный короткий ритм и придумать собственный ответ без требования пианино.", "skill":"music", "chapter":"chapter_03", "location":"workshop_annex", "kind":"practice", "budget":10},
	{"id":"MU05", "title":"Два настроения", "summary":"Сыграть или построить один короткий мотив в двух вариантах и выбрать звук для сцены.", "skill":"music", "chapter":"chapter_03", "location":"workshop_annex", "kind":"project", "budget":20},
	{"id":"MU07", "title":"Пауза тоже музыка", "summary":"Собрать ритм с паузами и объяснить, что изменилось в последовательности.", "skill":"music", "chapter":"chapter_03", "location":"workshop_annex", "kind":"practice", "budget":10},
	{"id":"WO01", "title":"Каталог мастерской", "summary":"Со взрослым разобрать названия нескольких имеющихся инструментов и их назначение.", "skill":"wood", "chapter":"chapter_03", "location":"workshop_annex", "kind":"practice", "budget":10, "adult":"required"},
	{"id":"WO03", "title":"Два варианта подставки", "summary":"Сравнить две формы декоративной настольной подставки и выбрать одну для эскиза.", "skill":"wood", "chapter":"chapter_03", "location":"workshop_annex", "kind":"planning", "budget":20},
	{"id":"WO05", "title":"Держатель карточки", "summary":"Собрать декоративный объект из заранее подготовленных деталей; опасные операции выполняет взрослый.", "skill":"wood", "chapter":"chapter_03", "location":"workshop_annex", "kind":"family_project", "budget":40, "adult":"required"},
	{"id":"HI01", "title":"Три слоя пейзажа", "summary":"Замечать передний, средний и дальний план с безопасной точки; можно выполнять из окна.", "skill":"outdoors", "chapter":"chapter_04", "location":"field_archive", "kind":"observation", "budget":10},
	{"id":"HI04", "title":"Следы без сбора", "summary":"Наблюдать формы листьев или камней без изъятия объектов и сделать зарисовку.", "skill":"outdoors", "chapter":"chapter_04", "location":"field_archive", "kind":"observation", "budget":10},
	{"id":"HI08", "title":"Страница экспедиции", "summary":"Собрать рисунок, наблюдение и одно предложение о семейной прогулке без точных координат.", "skill":"outdoors", "chapter":"chapter_04", "location":"field_archive", "kind":"project", "budget":20},
	{"id":"RL01", "title":"Устойчивая стойка", "summary":"На выбранной взрослым безопасной площадке отработать устойчивую стойку и спокойный старт на роликах.", "skill":"rollers", "chapter":"chapter_02", "location":"field_archive", "kind":"practice", "budget":10, "adult":"required"},
	{"id":"RL02", "title":"Торможу уверенно", "summary":"С взрослым потренировать один безопасный способ торможения и отметить, где остановка получилась контролируемой.", "skill":"rollers", "chapter":"chapter_02", "location":"field_archive", "kind":"practice", "budget":10, "adult":"required"},
	{"id":"RL03", "title":"Моя короткая линия", "summary":"Составить короткую последовательность из старта, поворота и остановки на заранее выбранной безопасной площадке.", "skill":"rollers", "chapter":"chapter_03", "location":"field_archive", "kind":"project", "budget":20, "adult":"required"},
	{"id":"MA01", "title":"Масштаб моей комнаты", "summary":"Построить упрощённый план вымышленной или своей комнаты с выбранным масштабом; адрес не нужен.", "skill":"math", "chapter":"chapter_03", "location":"workshop_annex", "kind":"project", "budget":20},
	{"id":"MA03", "title":"Узор по правилу", "summary":"Придумать повторяющийся узор и коротко описать правило его продолжения.", "skill":"math", "chapter":"chapter_03", "location":"workshop_annex", "kind":"project", "budget":20},
	{"id":"MA05", "title":"Сначала оценка", "summary":"Сначала оценить длину или количество, затем измерить и спокойно обсудить разницу.", "skill":"math", "chapter":"chapter_04", "location":"field_archive", "kind":"practice", "budget":10},
	{"id":"CO01", "title":"Команды для механизма", "summary":"Собрать последовательность из готовых безопасных игровых действий и проверить результат.", "skill":"programming", "chapter":"chapter_02", "location":"radio_cafe", "kind":"game_lab", "budget":10},
	{"id":"CO04", "title":"Найди маленькую ошибку", "summary":"Исправить специально подготовленный безопасный пример и объяснить разницу до и после.", "skill":"programming", "chapter":"chapter_03", "location":"workshop_annex", "kind":"game_lab", "budget":10},
	{"id":"CO05", "title":"Персонаж отвечает", "summary":"Создать локальную развилку из двух реплик в редакторе данных без облачного чата.", "skill":"programming", "chapter":"chapter_02", "location":"radio_cafe", "kind":"project", "budget":20}
]

const START_QUESTS: Array[Dictionary] = [
	{
		"schema_version": 1, "quest_id": "S00", "revision": 1,
		"content_status": "PUBLISHED", "kind": "builtin",
		"title": "Это моя станция",
		"summary": "Дать станции имя, выбрать символ, поставить экспонат и разгадать первую тайну.",
		"is_main_quest": true, "chapter_id": "chapter_01",
		"estimated_minutes": {"min": 5, "max": 10},
		"completion_criteria": ["Название и оформление сохраняются.", "Первая тайна станции разгадана."],
		"variants": [{"id": "inside_game", "title": "Внутри игры", "home_available": true}],
		"context": {"adult_presence": "release_approved", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["game_event"], "required_media": false, "reviewer": "game"},
		"reward_policy": {"activity_budget": 0, "lane": "project", "skill_weights_percent": {}, "world_effect_ids": []},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S01", "revision": 1,
		"content_status": "DRAFT", "kind": "observation",
		"title": "Карта начинается здесь",
		"summary": "Заметь три детали вокруг и сделай маленькую карту-набросок или три рисунка.",
		"is_main_quest": false, "chapter_id": "chapter_01",
		"estimated_minutes": {"min": 10, "max": 25},
		"completion_criteria": ["Есть три наблюдения.", "К одному наблюдению есть понятная подпись."],
		"variants": [{"id": "window", "title": "Наблюдения из окна", "home_available": true}, {"id": "family_walk", "title": "Семейная прогулка", "home_available": false}],
		"context": {"adult_presence": "for_outdoor_variant", "requires_purchase": false, "requires_network": false, "risk_tags": ["outdoor_optional"]},
		"evidence_policy": {"allowed": ["parent_observation", "local_image"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 20, "lane": "project", "skill_weights_percent": {"drawing": 100}, "world_effect_ids": ["atlas_first_page"]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S02", "revision": 1,
		"content_status": "DRAFT", "kind": "practice",
		"title": "Можно ещё раз?",
		"summary": "Разобрать приветствие, просьбу повторить и благодарность, а затем применить просьбу в выбранной сценке.",
		"is_main_quest": true, "chapter_id": "chapter_01",
		"estimated_minutes": {"min": 10, "max": 15},
		"completion_criteria": ["В выбранном контексте использована просьба повторить.", "Игрок объясняет, какой смысл удалось понять."],
		"variants": [{"id": "parent_roleplay", "title": "Сценка с родителем", "home_available": true}, {"id": "approved_dialogue", "title": "Готовый диалог", "home_available": true}],
		"context": {"adult_presence": "available", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["parent_observation", "note"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 10, "lane": "practice", "skill_weights_percent": {"spanish": 100}, "world_effect_ids": ["radio_channel_01_unlocked"]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S03", "revision": 1,
		"content_status": "DRAFT", "kind": "planning",
		"title": "План для маленькой вещи",
		"summary": "Измерить небольшой предмет и нарисовать план декоративной подставки или таблички с тремя размерами.",
		"is_main_quest": false, "chapter_id": "chapter_02",
		"estimated_minutes": {"min": 15, "max": 30},
		"completion_criteria": ["Три размера записаны с единицами.", "По рисунку понятен замысел."],
		"variants": [{"id": "real_measurement", "title": "Линейка и бумага", "home_available": true}, {"id": "given_dimensions", "title": "Готовые размеры", "home_available": true}],
		"context": {"adult_presence": "for_review", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["parent_observation", "local_image"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 20, "lane": "project", "skill_weights_percent": {"math": 75, "wood": 25}, "world_effect_ids": ["workbench_blueprint"]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S04", "revision": 1,
		"content_status": "DRAFT", "kind": "creative",
		"title": "Знак, которого здесь не было",
		"summary": "Придумать два маленьких варианта знака, выбрать один и объяснить форму, цвет или смысл.",
		"is_main_quest": false, "chapter_id": "chapter_02",
		"estimated_minutes": {"min": 15, "max": 40},
		"completion_criteria": ["Есть выбранный рисунок.", "Есть одно объяснение авторского решения."],
		"variants": [{"id": "paper", "title": "Бумага", "home_available": true}, {"id": "digital", "title": "Цифровой рисунок", "home_available": true}],
		"context": {"adult_presence": "for_import", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["parent_observation", "local_image"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 20, "lane": "project", "skill_weights_percent": {"drawing": 100}, "world_effect_ids": ["station_emblem_art"]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S05", "revision": 1,
		"content_status": "DRAFT", "kind": "music",
		"title": "Четыре ноты для маяка",
		"summary": "Придумать или выбрать короткий звуковой знак и повторить его в удобном темпе.",
		"is_main_quest": false, "chapter_id": "chapter_03",
		"estimated_minutes": {"min": 10, "max": 20},
		"completion_criteria": ["Согласованный короткий фрагмент можно воспроизвести или показать в конструкторе."],
		"variants": [{"id": "piano", "title": "Пианино или клавиатура", "home_available": true}, {"id": "screen_sequence", "title": "Экранный секвенсор", "home_available": true}, {"id": "clap_rhythm", "title": "Ритм хлопками", "home_available": true}],
		"context": {"adult_presence": "optional", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["parent_observation", "note"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 10, "lane": "practice", "skill_weights_percent": {"music": 100}, "world_effect_ids": ["station_motif"]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S06", "revision": 1,
		"content_status": "DRAFT", "kind": "family_project",
		"title": "Предмет с моей подписью",
		"summary": "Спроектировать и вместе со взрослым сделать маленькую декоративную вещь из заранее выбранных материалов.",
		"is_main_quest": false, "chapter_id": "chapter_03",
		"estimated_minutes": {"min": 30, "max": 120},
		"completion_criteria": ["Есть законченная декоративная вещь.", "Игрок может назвать свой вклад и вклад взрослого."],
		"variants": [{"id": "wood_with_parent", "title": "Деревянная заготовка со взрослым", "home_available": true}, {"id": "cardboard_story", "title": "Картонная сюжетная альтернатива", "home_available": true}],
		"context": {"adult_presence": "required_for_tools", "requires_purchase": false, "requires_network": false, "risk_tags": ["tools_parent_selected"]},
		"evidence_policy": {"allowed": ["parent_observation", "local_image"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 40, "lane": "project", "skill_weights_percent": {"wood": 75, "drawing": 25}, "world_effect_ids": ["author_artifact_card"], "milestones_percent": [25, 25, 50]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S07", "revision": 1,
		"content_status": "DRAFT", "kind": "planning",
		"title": "Рюкзак капитана экспедиции",
		"summary": "Для уже выбранной взрослым прогулки составить список вещей и обсудить время; можно пройти вымышленный пример дома.",
		"is_main_quest": false, "chapter_id": "chapter_04",
		"estimated_minutes": {"min": 15, "max": 25},
		"completion_criteria": ["Игрок объясняет несколько выбранных вещей.", "Понятно, кто принимает решения о маршруте и возвращении."],
		"variants": [{"id": "home_example", "title": "Вымышленный пример дома", "home_available": true}, {"id": "adult_selected_walk", "title": "План семейной прогулки", "home_available": false}],
		"context": {"adult_presence": "required_for_real_route", "requires_purchase": false, "requires_network": false, "risk_tags": ["outdoor_optional"]},
		"evidence_policy": {"allowed": ["parent_observation", "note"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 10, "lane": "practice", "skill_weights_percent": {"outdoors": 80, "math": 20}, "world_effect_ids": ["expedition_pack"]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S08", "revision": 1,
		"content_status": "DRAFT", "kind": "game_lab",
		"title": "Поменяй ветер",
		"summary": "Предсказать эффект параметра скорости, изменить его в безопасном конструкторе, сравнить результат и использовать сброс.",
		"is_main_quest": false, "chapter_id": "chapter_05",
		"estimated_minutes": {"min": 5, "max": 15},
		"completion_criteria": ["Показан параметр, который меняет поведение.", "Использован сброс к исходному состоянию."],
		"variants": [{"id": "presets", "title": "Готовые скорости", "home_available": true}, {"id": "number", "title": "Числовой параметр", "home_available": true}],
		"context": {"adult_presence": "optional", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["game_event", "parent_observation"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 10, "lane": "practice", "skill_weights_percent": {"programming": 100}, "world_effect_ids": ["wind_parameter_saved"]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S09", "revision": 1,
		"content_status": "DRAFT", "kind": "project",
		"title": "Вывеска для комнаты",
		"summary": "Создать понятную вывеску с короткой испанской надписью и визуальной подсказкой.",
		"is_main_quest": false, "chapter_id": "chapter_02",
		"estimated_minutes": {"min": 20, "max": 40},
		"completion_criteria": ["Есть законченная вывеска.", "Игрок объясняет смысл испанского текста."],
		"variants": [{"id": "paper", "title": "Бумага", "home_available": true}, {"id": "digital", "title": "Цифровая работа", "home_available": true}],
		"context": {"adult_presence": "for_review", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["parent_observation", "local_image"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 20, "lane": "project", "skill_weights_percent": {"drawing": 60, "spanish": 40}, "world_effect_ids": ["display_room_sign"]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S10", "revision": 1,
		"content_status": "DRAFT", "kind": "story_project",
		"title": "Восстановить канал",
		"summary": "Разобрать короткое сообщение, расположить три элемента по понятному правилу и выбрать ответ станции.",
		"is_main_quest": true, "chapter_id": "chapter_05",
		"estimated_minutes": {"min": 20, "max": 45},
		"completion_criteria": ["Последовательность объяснена.", "Смысл сообщения обсуждён.", "Выбран ответ станции."],
		"variants": [{"id": "cards", "title": "Карточки и подсказки", "home_available": true}, {"id": "custom_rule", "title": "Собственное правило", "home_available": true}],
		"context": {"adult_presence": "for_review", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["game_event", "parent_observation"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 40, "lane": "project", "skill_weights_percent": {"spanish": 50, "math": 50}, "world_effect_ids": ["observatory_view_01"], "milestones_percent": [25, 25, 50]},
		"provenance": {"origin": "design_brief"}
	},
	{
		"schema_version": 1, "quest_id": "S11", "revision": 1,
		"content_status": "DRAFT", "kind": "author_patch",
		"title": "Мой первый патч",
		"summary": "Изменить разрешённую реплику, увидеть предпросмотр, назвать версию и сохранить возможность отката.",
		"is_main_quest": false, "chapter_id": "chapter_05",
		"estimated_minutes": {"min": 10, "max": 25},
		"completion_criteria": ["Правка видна в предпросмотре.", "Есть история версии и рабочий откат."],
		"variants": [{"id": "dialogue", "title": "Редактор реплики", "home_available": true}],
		"context": {"adult_presence": "for_publish", "requires_purchase": false, "requires_network": false, "risk_tags": []},
		"evidence_policy": {"allowed": ["game_event", "parent_observation"], "required_media": false, "reviewer": "parent"},
		"reward_policy": {"activity_budget": 20, "lane": "project", "skill_weights_percent": {"programming": 100}, "world_effect_ids": ["author_patch_accepted"]},
		"provenance": {"origin": "design_brief"}
	}
]

static func all_templates() -> Array[Dictionary]:
	# Historical Phase A/B contract: this catalog is the 12-card starter set.
	# Phase C content is exposed through ContentLibraryService instead.
	return START_QUESTS.duplicate(true)

static func get_template(quest_id: String) -> Dictionary:
	for quest in START_QUESTS:
		if str(quest.get("quest_id", "")) == quest_id:
			return quest.duplicate(true)
	for quest in phase_c_templates():
		if str(quest.get("quest_id", "")) == quest_id:
			return quest.duplicate(true)
	return {}

static func get_skill_title(skill_id: String) -> String:
	return str(SKILLS.get(skill_id, {}).get("title", skill_id))

static func get_subskills(skill_id: String) -> Array:
	return SUBSKILLS.get(skill_id, []).duplicate(true)

static func real_quest_templates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for quest in START_QUESTS:
		if str(quest.get("quest_id", "")) != "S00":
			result.append(quest.duplicate(true))
	return result

static func phase_c_templates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for seed in PHASE_C_SEEDS:
		var budget := int(seed.get("budget", 10))
		var kind := str(seed.get("kind", "practice"))
		var skill := str(seed.get("skill", "drawing"))
		var adult := str(seed.get("adult", "for_review"))
		var repeat_max := 3 if kind in ["practice", "observation", "game_lab"] else 1
		result.append({
			"schema_version": 1,
			"quest_id": str(seed.get("id", "")),
			"revision": 1,
			"content_status": "DRAFT",
			"kind": kind,
			"title": str(seed.get("title", "")),
			"summary": str(seed.get("summary", "")),
			"is_main_quest": false,
			"chapter_id": str(seed.get("chapter", "chapter_02")),
			"location_id": str(seed.get("location", "radio_cafe")),
			"estimated_minutes": {"min": 10, "max": 35},
			"completion_criteria": ["Есть законченный результат, соответствующий описанию.", "Игрок может коротко объяснить, что именно сделал или заметил."],
			"variants": [{"id": "home", "title": "Домашний вариант", "home_available": true}],
			"context": {"adult_presence": adult, "requires_purchase": false, "requires_network": false, "risk_tags": ["adult_selected_tools"] if adult == "required" else []},
			"evidence_policy": {"allowed": ["parent_observation", "note", "local_image"], "required_media": false, "reviewer": "parent"},
			"reward_policy": {"activity_budget": budget, "lane": "project" if budget >= 20 else "practice", "skill_weights_percent": {skill: 100}, "world_effect_ids": []},
			"repeat_policy": {"mode": "limited" if repeat_max > 1 else "once", "max_completions": repeat_max},
			"provenance": {"origin": "phase_c_bank"}
		})
	return result

static func get_location(location_id: String) -> Dictionary:
	for location in PHASE_C_LOCATIONS:
		if str(location.get("location_id", "")) == location_id:
			return location.duplicate(true)
	return {}

static func get_default_dialogue() -> Dictionary:
	return {
		"radio_greeting": "Приветствуем новую хранительницу станции!",
		"archive_note": "Каждая хорошая карта начинается с первого наблюдения."
	}
