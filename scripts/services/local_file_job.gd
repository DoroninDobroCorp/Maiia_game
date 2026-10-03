class_name LocalFileJob
extends RefCounted

## File work owns an isolated snapshot; only the main thread commits player state.
const Backup = preload("res://scripts/services/backup_service.gd")
var worker := Thread.new()
var guard := Mutex.new()
var cancelled := false
var progress := {"phase":"prepare","done":0,"total":1}
var finished := false
var result: Dictionary = {}

func start_export(state: Dictionary, destination: String) -> Error:
	var isolated := state.duplicate(true)
	return worker.start(func(): return Backup.export_family_backup(isolated, destination, checkpoint))

func start_import(directory: String) -> Error:
	return worker.start(func(): return Backup.import_family_backup(directory, checkpoint))

func checkpoint(phase: String, done: int, total: int) -> bool:
	guard.lock()
	progress = {"phase":phase,"done":done,"total":maxi(1,total)}
	var proceed := not cancelled
	guard.unlock()
	return proceed

func cancel() -> void:
	guard.lock()
	cancelled = true
	guard.unlock()

func snapshot() -> Dictionary:
	guard.lock()
	var value := progress.duplicate()
	value["cancelled"] = cancelled
	guard.unlock()
	return value

func poll() -> bool:
	if finished: return true
	if worker.is_started() and not worker.is_alive():
		result = worker.wait_to_finish()
		finished = true
	return finished

func stop() -> void:
	cancel()
	if worker.is_started():
		result = worker.wait_to_finish()
		finished = true
