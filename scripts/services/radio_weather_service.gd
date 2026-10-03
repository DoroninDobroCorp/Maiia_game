class_name RadioWeatherService
extends Node

signal bulletin_ready(text: String)

const WEATHER_URL := "https://api.open-meteo.com/v1/forecast?latitude=-41.96&longitude=-71.53&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,wind_speed_10m_max&timezone=America%2FArgentina%2FSalta&forecast_days=2"
const DEFAULT_GATEWAY_URL := "http://127.0.0.1:8318/v1"
const MODEL := "gemini-3.8-flash-high"

var weather_request: HTTPRequest
var gemini_request: HTTPRequest
var busy := false
var fallback_bulletin := ""

func _ready() -> void:
	_ensure_requests()

func request_bulletin() -> bool:
	if busy:
		return false
	_ensure_requests()
	busy = true
	fallback_bulletin = ""
	var err := weather_request.request(WEATHER_URL)
	if err != OK:
		_finish("📻 Плохая связь. Прогноз из Эль-Больсона сейчас не проходит через эфир.")
		return false
	return true

func _ensure_requests() -> void:
	if weather_request == null:
		weather_request = HTTPRequest.new()
		weather_request.timeout = 8.0
		add_child(weather_request)
		weather_request.request_completed.connect(_on_weather_completed)
	if gemini_request == null:
		gemini_request = HTTPRequest.new()
		gemini_request.timeout = 14.0
		add_child(gemini_request)
		gemini_request.request_completed.connect(_on_gemini_completed)

func _on_weather_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_finish("📻 Плохая связь. Не удалось получить прогноз Эль-Больсона на сегодня и завтра.")
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_finish("📻 Плохая связь. Сигнал есть, но прогноз пришёл нечитаемым.")
		return
	var daily: Dictionary = (parsed as Dictionary).get("daily", {})
	fallback_bulletin = format_weather_daily(daily)
	if fallback_bulletin.is_empty():
		_finish("📻 Плохая связь. В прогнозе не хватает данных на два дня.")
		return
	_request_gemini_polish(fallback_bulletin)

func _request_gemini_polish(source_text: String) -> void:
	var api_key := OS.get_environment("SUR_VIBEPROXY_API_KEY").strip_edges()
	if api_key.is_empty():
		_finish(source_text)
		return
	var gateway_url := OS.get_environment("SUR_VIBEPROXY_URL").strip_edges()
	if gateway_url.is_empty():
		gateway_url = DEFAULT_GATEWAY_URL
	gateway_url = gateway_url.trim_suffix("/")
	var payload := {
		"model": MODEL,
		"messages": [
			{
				"role": "system",
				"content": "Ты короткий радиодиктор семейной игры. Переформулируй только переданные данные прогноза на русском. Две короткие строки: Сегодня... и Завтра.... Обязательно сохрани все числа (температуру, мм осадков в день, вероятность, ветер) и словесное описание осадков (например, много дождя, совсем немного дождя или без осадков). Ничего не выдумывай, не добавляй советы и предупреждения."
			},
			{"role": "user", "content": source_text}
		],
		"temperature": 0.2,
		"max_tokens": 240
	}
	var headers := PackedStringArray([
		"Authorization: Bearer " + api_key,
		"Content-Type: application/json"
	])
	var err := gemini_request.request(gateway_url + "/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_finish(source_text)

func _on_gemini_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_finish(fallback_bulletin)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		_finish(fallback_bulletin)
		return
	var choices: Variant = (parsed as Dictionary).get("choices", [])
	if typeof(choices) != TYPE_ARRAY or (choices as Array).is_empty():
		_finish(fallback_bulletin)
		return
	var first: Variant = (choices as Array)[0]
	if typeof(first) != TYPE_DICTIONARY:
		_finish(fallback_bulletin)
		return
	var message: Variant = (first as Dictionary).get("message", {})
	if typeof(message) != TYPE_DICTIONARY:
		_finish(fallback_bulletin)
		return
	var text := str((message as Dictionary).get("content", "")).strip_edges()
	if text.is_empty():
		_finish(fallback_bulletin)
		return
	_finish("📻 Эль-Больсон • эфир погоды\n" + text)

func _finish(text: String) -> void:
	busy = false
	bulletin_ready.emit(text)

static func format_weather_daily(daily: Dictionary) -> String:
	var times: Array = daily.get("time", [])
	var codes: Array = daily.get("weather_code", [])
	var max_t: Array = daily.get("temperature_2m_max", [])
	var min_t: Array = daily.get("temperature_2m_min", [])
	var rain: Array = daily.get("precipitation_probability_max", [])
	var wind: Array = daily.get("wind_speed_10m_max", [])
	var precip_sums: Array = daily.get("precipitation_sum", [])
	if times.size() < 2 or codes.size() < 2 or max_t.size() < 2 or min_t.size() < 2 or rain.size() < 2 or wind.size() < 2:
		return ""
	var p_today: float = float(precip_sums[0]) if precip_sums.size() > 0 else _default_precip_for_code(int(codes[0]), int(rain[0]))
	var p_tomorrow: float = float(precip_sums[1]) if precip_sums.size() > 1 else _default_precip_for_code(int(codes[1]), int(rain[1]))
	var today := "Сегодня: %s, %.0f…%.0f °C, осадки до %d%% (%s, %s), ветер до %.0f км/ч." % [
		_weather_name(int(codes[0])), float(min_t[0]), float(max_t[0]), int(rain[0]),
		_precipitation_words(p_today, int(codes[0])), _format_precip_amount(p_today), float(wind[0])
	]
	var tomorrow := "Завтра: %s, %.0f…%.0f °C, осадки до %d%% (%s, %s), ветер до %.0f км/ч." % [
		_weather_name(int(codes[1])), float(min_t[1]), float(max_t[1]), int(rain[1]),
		_precipitation_words(p_tomorrow, int(codes[1])), _format_precip_amount(p_tomorrow), float(wind[1])
	]
	return "📻 Эль-Больсон • эфир погоды\n%s\n%s" % [today, tomorrow]

static func _format_precip_amount(amount_mm: float) -> String:
	if amount_mm <= 0.05:
		return "0 мм в день"
	if is_equal_approx(amount_mm, roundf(amount_mm)):
		return "%d мм в день" % int(roundf(amount_mm))
	return "%.1f мм в день" % amount_mm

static func _precipitation_words(amount_mm: float, code: int) -> String:
	var is_snow := code in [71, 73, 75, 77, 85, 86]
	if amount_mm < 0.1:
		return "без осадков"
	if amount_mm < 2.0:
		return "совсем немного снега" if is_snow else "совсем немного дождя"
	if amount_mm < 6.0:
		return "небольшой снег" if is_snow else "небольшой дождь"
	if amount_mm < 15.0:
		return "умеренный снегопад" if is_snow else "умеренный дождь"
	if amount_mm < 30.0:
		return "много снега" if is_snow else "много дождя"
	return "очень много снега" if is_snow else "очень много дождя"

static func _default_precip_for_code(code: int, prob: int) -> float:
	if prob <= 10:
		return 0.0
	if code in [51, 53, 55, 56, 57]:
		return 1.2
	if code in [61, 80]:
		return 3.0
	if code in [63, 81]:
		return 8.0
	if code in [65, 66, 67, 82, 95, 96, 99]:
		return 18.0
	if code in [71, 73, 75, 77, 85, 86]:
		return 4.0
	return 0.0

static func _weather_name(code: int) -> String:
	if code == 0:
		return "ясно"
	if code in [1, 2]:
		return "переменная облачность"
	if code == 3:
		return "пасмурно"
	if code in [45, 48]:
		return "туман"
	if code in [51, 53, 55, 56, 57]:
		return "морось"
	if code in [61, 63, 65, 66, 67, 80, 81, 82]:
		return "дождь"
	if code in [71, 73, 75, 77, 85, 86]:
		return "снег"
	if code in [95, 96, 99]:
		return "гроза"
	return "облачно"
