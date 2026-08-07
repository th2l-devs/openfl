package openfl.display._internal;

#if !flash
import openfl.display.BitmapData;
import openfl.display.Shader;
import openfl.display.ShaderInput;
import openfl.display.ShaderParameter;

/**
	Composites an isolated group against a copy of the backdrop, for the blend modes that
	fixed-function blending cannot express.

	`OVERLAY`, `HARDLIGHT` and `DIFFERENCE` are per-component color math - a conditional keyed on
	the destination, a conditional keyed on the source, and an absolute value respectively - and no
	combination of `glBlendFunc` factors produces any of them. `MULTIPLY` is included because the
	usual `DESTINATION_COLOR, ONE_MINUS_SOURCE_ALPHA` state is only an approximation once both
	source and destination are partly transparent.

	The shader does the compositing itself and writes the finished pixel, so it must be drawn with
	the blend state set to replace (`ONE, ZERO`) rather than source-over.

	The formulas are the premultiplied ones from the `KHR_blend_equation_advanced` specification:

	```
	result.rgb = f(Cs, Cd) * As * Ad + Cs * As * (1 - Ad) + Cd * Ad * (1 - As)
	result.a   = As + Ad * (1 - As)
	```

	where `Cs`/`Cd` are the un-premultiplied source and destination colors. Because both inputs
	arrive premultiplied, they are divided through by their alpha first.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class Context3DBlendShader extends Shader
{
	/** `uBlendMode` value selecting the `MULTIPLY` formula. **/
	public static inline var MODE_MULTIPLY:Int = 0;

	/** `uBlendMode` value selecting the `OVERLAY` formula. **/
	public static inline var MODE_OVERLAY:Int = 1;

	/** `uBlendMode` value selecting the `HARDLIGHT` formula. **/
	public static inline var MODE_HARDLIGHT:Int = 2;

	/** `uBlendMode` value selecting the `DIFFERENCE` formula. **/
	public static inline var MODE_DIFFERENCE:Int = 3;

	@:glFragmentSource("varying vec2 openfl_TextureCoordv;

		uniform sampler2D openfl_Texture;
		uniform sampler2D uBackdrop;
		uniform float openfl_Alpha;
		uniform float uBlendMode;
		uniform float uBackdropFlip;

		vec3 blendHardLight (vec3 src, vec3 dst) {

			// 2 * src * dst where src <= 0.5, screen otherwise; step() keeps it branch-free
			vec3 multiply = 2.0 * src * dst;
			vec3 screen = 1.0 - 2.0 * (1.0 - src) * (1.0 - dst);
			return mix (multiply, screen, step (vec3 (0.5), src));

		}

		vec3 blendFunction (vec3 src, vec3 dst) {

			if (uBlendMode < 0.5) {

				return src * dst;

			} else if (uBlendMode < 1.5) {

				// overlay is hard-light with the operands swapped
				return blendHardLight (dst, src);

			} else if (uBlendMode < 2.5) {

				return blendHardLight (src, dst);

			}

			return abs (dst - src);

		}

		void main(void) {

			vec4 src = texture2D (openfl_Texture, openfl_TextureCoordv) * openfl_Alpha;

			vec2 backdropCoord = openfl_TextureCoordv;
			if (uBackdropFlip < 0.0) backdropCoord.y = 1.0 - backdropCoord.y;
			vec4 dst = texture2D (uBackdrop, backdropCoord);

			if (src.a == 0.0) {

				gl_FragColor = dst;

			} else {

				// Un-premultiply both inputs before applying the blend function
				vec3 cs = src.rgb / src.a;
				vec3 cd = dst.a > 0.0 ? dst.rgb / dst.a : vec3 (0.0);

				vec3 blended = blendFunction (cs, cd);

				vec3 rgb = blended * src.a * dst.a
					+ cs * src.a * (1.0 - dst.a)
					+ cd * dst.a * (1.0 - src.a);

				gl_FragColor = vec4 (rgb, src.a + dst.a * (1.0 - src.a));

			}

		}")
	@:glVertexSource("attribute vec4 openfl_Position;
		attribute vec2 openfl_TextureCoord;
		varying vec2 openfl_TextureCoordv;

		uniform mat4 openfl_Matrix;

		void main(void) {

			openfl_TextureCoordv = openfl_TextureCoord;

			gl_Position = openfl_Matrix * openfl_Position;

		}")
	public function new()
	{
		super();
	}

	/**
		Points the shader at `backdrop` and selects the blend formula.

		The custom uniforms are reached through `data` rather than as fields on this class.
		`Shader.__processGLData` always registers them there, while the typed fields only exist
		when the `@:autoBuild` macro emitted them - which not every Haxe version does. `data` is
		the contract that holds either way, and this runs once per blended object, so the dynamic
		lookup costs nothing that matters.

		@param	flip	`-1` when the backdrop's texture rows run opposite to the source's.
	**/
	public function apply(backdrop:BitmapData, mode:Int, flip:Float):Void
	{
		var backdropInput:ShaderInput<BitmapData> = data.uBackdrop;

		if (backdropInput != null)
		{
			backdropInput.input = backdrop;
			backdropInput.filter = NEAREST;
		}

		var blendMode:ShaderParameter<Float> = data.uBlendMode;
		if (blendMode != null) blendMode.value = [mode];

		var backdropFlip:ShaderParameter<Float> = data.uBackdropFlip;
		if (backdropFlip != null) backdropFlip.value = [flip];
	}
}
#end
