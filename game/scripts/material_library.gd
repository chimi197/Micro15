## The game's material families and palette (docs/art_direction.md).
## Every imported glTF material is matched by name to a family, which picks
## its shader, roughness, specular, surface variation and grime; the
## palette can replace a model's colour so the whole map stays in one
## coordinated range. Add a family or a colour here, not in the models.
@tool
class_name MaterialLibrary
extends RefCounted

## family: shader parameters (shader defaults to stylized)
const FAMILIES := {
	"plaster": {"roughness": 0.9, "specular": 0.25, "variation": 0.06, "variation_scale": 9.0, "grime": 0.16,
			"grime_height": 1.6},
	"concrete": {"roughness": 0.95, "specular": 0.2, "variation": 0.08, "grime": 0.12},
	"roof": {"roughness": 0.95, "specular": 0.15, "variation": 0.08},
	"asphalt": {"roughness": 0.95, "specular": 0.15, "variation": 0.07, "variation_scale": 14.0, "speckle": 0.05},
	"paving": {"roughness": 0.9, "specular": 0.2, "variation": 0.06, "seams": 0.12, "seam_size": 1.0},
	"gravel": {"roughness": 1.0, "specular": 0.1, "variation": 0.1, "speckle": 0.08},
	"paint": {"roughness": 0.8, "specular": 0.2, "variation": 0.04},
	"painted_metal": {"roughness": 0.55, "specular": 0.35, "variation": 0.03},
	"bare_metal": {"roughness": 0.4, "specular": 0.5, "metallic": 0.3, "variation": 0.02},
	"gilded": {"roughness": 0.35, "specular": 0.5, "metallic": 0.6},
	"wood": {"roughness": 0.8, "specular": 0.2, "variation": 0.06, "variation_scale": 2.0},
	"bark": {"roughness": 0.95, "specular": 0.1, "variation": 0.1, "variation_scale": 1.5},
	"glass": {"roughness": 0.08, "specular": 0.6},
	"lamp_glass": {"roughness": 0.3, "specular": 0.4, "glow": 0.25},
	"fabric": {"roughness": 1.0, "specular": 0.1, "variation": 0.02},
	"rubber": {"roughness": 0.9, "specular": 0.15},
	"soil": {"roughness": 1.0, "specular": 0.05, "variation": 0.12, "speckle": 0.1},
	"skin": {"roughness": 0.65, "specular": 0.3},
	"hair": {"roughness": 0.55, "specular": 0.35},
	"cloth": {"roughness": 0.95, "specular": 0.15},
	"eye": {"roughness": 0.2, "specular": 0.5},
	"foliage": {"shader": "foliage", "light_wrap": 0.45},
	"lawn": {"shader": "lawn", "light_wrap": 0.3},
}

## Material name (without C3_/CH_) starts with: family. First match wins.
const MATCH := [
	["lamp_glass", "lamp_glass"], ["glass", "glass"],
	["church_roof", "roof"], ["roof_tile", "roof"], ["roof_dark", "roof"], ["roof_box", "concrete"],
	["roof", "roof"], ["retail_band", "paint"], ["garage_wall", "plaster"],
	["wall", "plaster"], ["house", "plaster"], ["school", "plaster"], ["church", "plaster"],
	["hospital", "plaster"], ["retail", "plaster"], ["parapet", "plaster"],
	["plinth", "concrete"], ["slab", "concrete"], ["kerb", "concrete"], ["step", "concrete"],
	["canopy", "concrete"], ["concrete", "concrete"], ["chess_dark", "concrete"],
	["asphalt", "asphalt"], ["parking", "asphalt"], ["pavement", "paving"], ["path", "gravel"],
	["sand", "gravel"], ["line", "paint"], ["lawn", "lawn"], ["pitch", "lawn"],
	["metal_grey", "bare_metal"], ["metal", "painted_metal"], ["fence", "painted_metal"],
	["bin", "painted_metal"], ["container", "painted_metal"], ["dish", "painted_metal"], ["ac", "painted_metal"],
	["garage_door", "painted_metal"], ["door_metal", "painted_metal"], ["frame", "paint"], ["door", "paint"],
	["gold", "gilded"], ["wood", "wood"], ["bark", "bark"], ["trunk", "bark"], ["birch_bark", "bark"],
	["birch_leaf", "foliage"],
	["curtain", "fabric"], ["rubber", "rubber"], ["soil", "soil"],
	["leaf", "foliage"], ["poplar", "foliage"], ["bush", "foliage"], ["hedge", "foliage"], ["pine", "foliage"],
	["plant", "foliage"], ["flower", "paint"],
	["red", "painted_metal"], ["yellow", "painted_metal"], ["blue", "painted_metal"], ["white", "painted_metal"],
	["skin", "skin"], ["hair", "hair"], ["brow", "hair"], ["sclera", "eye"], ["iris", "eye"], ["pupil", "eye"],
	["lid", "hair"], ["mouth", "skin"], ["shirt", "cloth"], ["shorts", "cloth"], ["sock", "cloth"],
	["shoe", "cloth"], ["sole", "rubber"], ["stripe", "cloth"],
]

## Coordinated colours (sRGB) replacing the model's colour, by full name.
const PALETTE := {
	# blocks of flats: soft warm pastels, saturation <= 30 %, value 75-90 %
	"C3_wall_f2e3b3": "#eadcb6", "C3_wall_f7d774": "#e9d18f", "C3_wall_ebe7dc": "#e4dfd2",
	"C3_wall_9ec9e2": "#adc5d3", "C3_wall_c9b6e4": "#c6bdd4", "C3_wall_a8d8b9": "#b6cfb4",
	"C3_wall_f4b183": "#e6bc9a", "C3_wall_e98b6d": "#d49d85",
	"C3_house_f6e7c1": "#ece0c2", "C3_house_f2c59a": "#e3c3a3", "C3_house_e8f0d0": "#dfe5cc",
	"C3_house_f5d5d5": "#e8d3cd", "C3_house_d6e8f2": "#d3dfe4", "C3_house_fbe9a0": "#ecdfa9",
	"C3_house_ffffff": "#efebe3", "C3_school": "#dfb877", "C3_plinth": "#8a8178", "C3_parapet_white": "#e9e4d8",
	"C3_slab": "#cfc8b8", "C3_roof": "#7d7a74", "C3_roof_tile": "#b0583f", "C3_roof_dark": "#6a4a3e",
	# ground
	"C3_asphalt": "#65686f", "C3_parking": "#6f727a", "C3_pavement": "#cfc7b6", "C3_kerb": "#a9a194",
	"C3_path": "#d6c49a", "C3_sand": "#dcc595", "C3_line": "#ebe6d6", "C3_lawn": "#84a656",
	"C3_pitch": "#6f9a4e",
	# foliage
	"C3_leaf_a": "#5f9748", "C3_leaf_b": "#77a84c", "C3_leaf_c": "#4e8443", "C3_poplar": "#4a7f45",
	"C3_bush": "#5c9446", "C3_hedge_bush": "#56893f", "C3_pine_leaf": "#3e6b57", "C3_birch_leaf": "#97bd5d",
	"C3_plant": "#5c9446",
	# wood, bark, metal
	"C3_bark": "#7a5a43", "C3_trunk": "#6f523d", "C3_wood": "#b07a4b", "C3_metal": "#4b5059",
	"C3_metal_dark": "#41464e", "C3_fence_green": "#3f6e4a", "C3_bin_green": "#447a50",
	"C3_container": "#3b6447",
}

const SHADERS := {
	"stylized": preload("res://shaders/stylized.gdshader"),
	"foliage": preload("res://shaders/foliage.gdshader"),
	"lawn": preload("res://shaders/lawn.gdshader"),
}
const NOISE := preload("res://style/noise.tres")


static func family_of(material_name: String) -> String:
	var n := material_name.trim_prefix("C3_").trim_prefix("CH_").to_lower()
	for m: Array in MATCH:
		if n.begins_with(m[0]):
			return m[1]
	return "paint"


static func colour_of(material_name: String, model_colour: Color) -> Color:
	return Color(PALETTE[material_name]) if PALETTE.has(material_name) else model_colour


## A new material for an imported one.
static func make(material_name: String, model_colour: Color, instance_tint := false) -> ShaderMaterial:
	var fam: Dictionary = FAMILIES[family_of(material_name)]
	var mat := ShaderMaterial.new()
	mat.resource_name = material_name
	mat.shader = SHADERS[fam.get("shader", "stylized")]
	var colour := colour_of(material_name, model_colour)
	mat.set_shader_parameter("tint", colour)
	mat.set_shader_parameter("noise_tex", NOISE)
	for key: String in fam:
		match key:
			"shader":
				pass
			"glow":
				mat.set_shader_parameter("emission", Color(colour) * fam.glow)
			_:
				mat.set_shader_parameter(key, fam[key])
	if mat.shader == SHADERS.stylized:
		mat.set_shader_parameter("instance_tint", instance_tint)
	return mat
