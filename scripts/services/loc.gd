## Interface texts in Russian, English and Uzbek. The language follows the device unless the
## player picked one in the settings.
extends Node

const LANGS := ["ru", "en", "uz"]
const NAMES := {"ru": "Русский", "en": "English", "uz": "Oʻzbekcha"}

const T := {
	"play": ["Играть", "Play", "Oʻynash"],
	"levels": ["Уровни", "Levels", "Bosqichlar"],
	"balls": ["Мячи", "Balls", "Sharlar"],
	"settings": ["Настройки", "Settings", "Sozlamalar"],
	"tagline": ["Катись. Преодолевай. Стань легендой.", "Roll. Overcome. Become a legend.", "Dumala. Yeng. Afsonaga aylan."],
	"level_n": ["Уровень %d", "Level %d", "%d-bosqich"],
	"world_1": ["Небесные острова", "Sky Islands", "Osmon orollari"],
	"world_2": ["Пустынный каньон", "Desert Canyon", "Choʻl kanyoni"],
	"world_3": ["Неоновые ночи", "Neon Nights", "Neon tunlari"],
	"pause": ["Пауза", "Paused", "Pauza"],
	"resume": ["Продолжить", "Resume", "Davom etish"],
	"restart": ["Заново", "Restart", "Qaytadan"],
	"to_map": ["К уровням", "Levels", "Bosqichlarga"],
	"to_menu": ["В меню", "Menu", "Menyuga"],
	"next": ["Дальше", "Next", "Keyingi"],
	"retry": ["Повторить", "Try again", "Qayta urinish"],
	"level_done": ["Уровень пройден!", "Level complete!", "Bosqich oʻtildi!"],
	"fell": ["Шар упал", "The ball fell", "Shar yiqildi"],
	"no_lives": ["Попытки закончились", "Out of tries", "Urinishlar tugadi"],
	"continue_ad": ["Продолжить за рекламу", "Continue (watch ad)", "Reklama evaziga davom etish"],
	"double_ad": ["Удвоить за рекламу", "Double (watch ad)", "Reklama evaziga ikki barobar"],
	"ad_unavailable": ["Реклама сейчас недоступна", "No ad available right now", "Hozir reklama mavjud emas"],
	"reward": ["Награда", "Reward", "Mukofot"],
	"time": ["Время", "Time", "Vaqt"],
	"record": ["Рекорд!", "New record!", "Rekord!"],
	"star_2": ["Соберите кристаллов: %d", "Collect %d crystals", "%d ta kristall yigʻing"],
	"star_3": ["Без падений", "No falls", "Yiqilmasdan"],
	"star_3_time": ["Без падений, быстрее %d с", "No falls, under %d s", "Yiqilmasdan, %d s dan tez"],
	"hint_steer": ["Ведите пальцем влево и вправо", "Slide your finger left and right", "Barmoqni chapga va oʻngga suring"],
	"hint_crystals": ["Собирайте кристаллы", "Collect the crystals", "Kristallarni yigʻing"],
	"hint_edge": ["Не упадите с края", "Do not fall off the edge", "Chetdan yiqilib tushmang"],
	"hint_gap": ["Разгон — и шар перепрыгнет сам", "Keep rolling - the ball jumps by itself", "Tezlikni saqlang — shar oʻzi sakraydi"],
	"hint_checkpoint": ["Кольцо — точка возврата", "The ring is your checkpoint", "Halqa — qaytish nuqtasi"],
	"checkpoint": ["Чекпоинт!", "Checkpoint!", "Nazorat nuqtasi!"],
	"skin_classic": ["Классика", "Classic", "Klassik"],
	"skin_neon_pulse": ["Неоновый пульс", "Neon Pulse", "Neon puls"],
	"skin_gold_core": ["Золотое ядро", "Gold Core", "Oltin yadro"],
	"skin_lava": ["Лава", "Lava", "Lava"],
	"skin_retro_pixel": ["Ретро-пиксель", "Retro Pixel", "Retro piksel"],
	"skin_storm": ["Шторм", "Storm", "Boʻron"],
	"selected": ["Выбран", "Selected", "Tanlangan"],
	"select": ["Выбрать", "Select", "Tanlash"],
	"need_level": ["Пройдите уровень %d", "Finish level %d", "%d-bosqichni oʻting"],
	"need_stars": ["Соберите звёзд: %d", "Earn %d stars", "%d ta yulduz yigʻing"],
	"not_enough": ["Не хватает кристаллов", "Not enough crystals", "Kristallar yetarli emas"],
	"sound": ["Звук", "Sound", "Ovoz"],
	"vibration": ["Вибрация", "Vibration", "Tebranish"],
	"sensitivity": ["Чувствительность", "Sensitivity", "Sezgirlik"],
	"language": ["Язык", "Language", "Til"],
	"privacy": ["Политика конфиденциальности", "Privacy policy", "Maxfiylik siyosati"],
	"ad_choices": ["Настройки рекламы", "Ad privacy options", "Reklama sozlamalari"],
	"on": ["Вкл", "On", "Yoniq"],
	"off": ["Выкл", "Off", "Oʻchiq"],
	"locked": ["Сначала пройдите предыдущий уровень", "Finish the previous level first", "Avval oldingi bosqichni oʻting"],
	"back": ["Назад", "Back", "Orqaga"],
	"campaign_done": ["Кампания пройдена!", "Campaign complete!", "Kampaniya oʻtildi!"],
	"new_skin": ["Новый мяч: %s", "New ball: %s", "Yangi shar: %s"],
}

var lang := "en"

func _ready() -> void:
	refresh()

func refresh() -> void:
	var want: String = Progress.language
	if want == "":
		want = OS.get_locale_language()
	lang = want if LANGS.has(want) else "en"

func t(key: String) -> String:
	if not T.has(key):
		return key
	return T[key][LANGS.find(lang)]

func f(key: String, arg) -> String:
	return t(key) % arg
