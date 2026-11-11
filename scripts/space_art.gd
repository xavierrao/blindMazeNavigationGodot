class_name SpaceArt
extends RefCounted
## Loads and draws the space artwork. To change which picture a space uses,
## edit FILES below. If a picture is missing, the views fall back to the old
## colored circle, so you can add the art a few tiles at a time.

const FOLDER := "res://art/spaces/"

# space type -> file name inside FOLDER
const FILES := {
	"Start": "start.png",
	"Neutral": "neutral.png",
	"Good": "good.png",
	"Bad": "bad.png",
	"Shop": "shop.png",
	"Crown": "crown.png",
	"Shadow Realm": "shadow_realm.png",
	"Combat": "combat.png",
	"Teleport": "teleport.png",
}

## How the pictures are smoothed when drawn smaller than they really are.
## LINEAR looks best while your tiles are still large (hundreds of pixels).
## Once they are small pixel art (say 64-128 px), switch to NEAREST for crisp pixels:
##   CanvasItem.TEXTURE_FILTER_NEAREST
const FILTER := CanvasItem.TEXTURE_FILTER_LINEAR

static var _cache := {}


static func get_texture(type_name: String) -> Texture2D:
	if _cache.has(type_name):
		return _cache[type_name]
	var texture: Texture2D = null
	if FILES.has(type_name):
		var path: String = FOLDER + FILES[type_name]
		if ResourceLoader.exists(path):
			texture = load(path)
	_cache[type_name] = texture
	return texture


## Draws a space's picture centered on a point, fitted inside a square of the
## given size. Returns false if there is no picture for that type, so the
## caller can draw its own fallback. Call this from inside a _draw() function.
static func draw_space(canvas: CanvasItem, type_name: String, center: Vector2, diameter: float) -> bool:
	var texture := get_texture(type_name)
	if texture == null:
		return false
	var texture_size := texture.get_size()
	var fitted := texture_size * (diameter / maxf(texture_size.x, texture_size.y))
	canvas.draw_texture_rect(texture, Rect2(center - fitted / 2.0, fitted), false)
	return true
