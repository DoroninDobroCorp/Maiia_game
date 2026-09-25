extends Node

## Скрипт автоматического прогона и снятия реальных игровых скриншотов (A07)

const SaveServiceScript = preload("res://scripts/services/save_service.gd")
const AppRootScene = preload("res://scenes/app/app_root.tscn")

var app: Node
var step: int = 0
var frame_counter: int = 0

func _ready() -> void:
	# Сбрасываем сохранение для чистого прогона с самого начала
	SaveServiceScript.reset_save()
	
	app = AppRootScene.instantiate()
	add_child(app)

func _process(_delta: float) -> void:
	frame_counter += 1
	
	if frame_counter == 15 and step == 0:
		step = 1
		# Кадр 1: Исходный вид станции (Фаза 1: сумерки, лампа выключена)
		app.take_screenshot("screenshots/01_station_initial_dusk.png")
		print("Captured 01_station_initial_dusk.png")
		
	elif frame_counter == 30 and step == 1:
		step = 2
		# Открываем терминал автора
		app.open_author_terminal()
		
	elif frame_counter == 45 and step == 2:
		step = 3
		# Кадр 2: Терминал автора
		app.take_screenshot("screenshots/02_author_terminal.png")
		print("Captured 02_author_terminal.png")
		# Применяем авторское оформление: «Маяк Рио Асуль», символ «feather», экспонат «crystal»
		app.apply_author_customization("Маяк Рио Асуль", "feather", "crystal")
		app._close_modals()
		
	elif frame_counter == 60 and step == 3:
		step = 4
		# Открываем шкатулку с дисками и включаем подсказку
		app.open_puzzle_box()
		var puzzle_ui: Node = app.modal_container.get_child(0)
		if puzzle_ui != null and puzzle_ui.has_method("_on_hint_pressed"):
			puzzle_ui._on_hint_pressed()
			
	elif frame_counter == 75 and step == 4:
		step = 5
		# Кадр 3: Мини-игра дисков с открытой подсказкой
		app.take_screenshot("screenshots/03_puzzle_dials_clue.png")
		print("Captured 03_puzzle_dials_clue.png")
		# Решаем загадку и закрываем модальное окно, чтобы увидеть преображённую комнату
		app.complete_puzzle()
		app._close_modals()
		
	elif frame_counter == 105 and step == 5:
		step = 6
		# Кадр 4: Пробуждённая станция (Фаза 2: тёплый свет лампы, радио светится, кристалл и вывеска)
		app.take_screenshot("screenshots/04_station_awakened_stage2.png")
		print("Captured 04_station_awakened_stage2.png")
		# Открываем журнал станции
		app.open_journal()
		
	elif frame_counter == 120 and step == 6:
		step = 7
		# Кадр 5: Полевой журнал с выполненным прологом S00 (4/4)
		app.take_screenshot("screenshots/05_station_journal_complete.png")
		print("Captured 05_station_journal_complete.png")
		app._close_modals()
		
	elif frame_counter == 130 and step == 7:
		print("All 5 acceptance screenshots captured successfully!")
		get_tree().quit(0)
