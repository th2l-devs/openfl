package openfl.display._internal;

#if !flash
import openfl.display.BlendMode;

/**
	Classifies each `BlendMode` by the mechanism the GL renderer needs in order to produce it.

	The 15 Flash blend modes are not homogeneous. Some are a plain `glBlendFunc`/`glBlendEquation`
	state; some are per-component color math that fixed-function blending cannot express and that
	therefore needs the backdrop as a shader input; and three of them (`ALPHA`, `ERASE`, `LAYER`)
	are not a blend state at all but a group-compositing operation that only means anything
	against an isolated transparency group.

	Keeping that classification in one place is what lets the renderer, the cache-bitmap logic and
	the shader all agree on which path a given mode takes, instead of each re-deriving it.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
class BlendModeSupport
{
	/**
		Whether `mode` is produced entirely by fixed-function blend state, with no render-target
		read and no isolated group.
	**/
	public static function isFixedFunction(mode:BlendMode):Bool
	{
		return switch (mode)
		{
			case NORMAL, ADD, SCREEN, SUBTRACT, MULTIPLY, INVERT: true;
			// GL_MIN / GL_MAX are only reachable where desktop GL blend equations exist
			case DARKEN, LIGHTEN: #if desktop true #else false #end;
			default: false;
		}
	}

	/**
		Whether `mode` is one of the three group-compositing modes.

		`LAYER` forces an isolated transparency group; `ALPHA` and `ERASE` are the Porter-Duff
		`destination-in` and `destination-out` operators, which are only meaningful *inside* such
		a group - applied straight to the main framebuffer, `ERASE` would punch a hole through
		everything already drawn rather than through the group alone.
	**/
	public static function isGroupMode(mode:BlendMode):Bool
	{
		return switch (mode)
		{
			case ALPHA, ERASE, LAYER: true;
			default: false;
		}
	}

	/**
		Whether producing `mode` requires reading the backdrop in a fragment shader.

		These are the separable color-math modes with a per-component conditional or an absolute
		value, which no combination of `glBlendFunc` factors can express.
	**/
	public static function needsBackdrop(mode:BlendMode):Bool
	{
		return switch (mode)
		{
			case DIFFERENCE, HARDLIGHT, OVERLAY, SHADER: true;
			default: false;
		}
	}

	/**
		Whether `mode` only means anything when the object's parent is itself an isolated group.

		`ALPHA` and `ERASE` composite against the group buffer rather than against the object
		behind them, so - exactly as the Flash documentation states - the parent's `blendMode`
		has to be `LAYER` for them to do anything.
	**/
	public static function isGroupChildMode(mode:BlendMode):Bool
	{
		return switch (mode)
		{
			case ALPHA, ERASE: true;
			default: false;
		}
	}

	/**
		Whether an object using `mode` has to be composited through an isolated offscreen group
		rather than drawn straight into the current render target.

		This is what the cache-bitmap path keys off: a `true` here means the object gets rendered
		into its own buffer first, exactly as it would if it carried a filter.

		`ALPHA` and `ERASE` are deliberately not included - they don't isolate the object that
		carries them, they require the *parent* to be isolated. See `isGroupChildMode`.
	**/
	public static function needsIsolatedGroup(mode:BlendMode):Bool
	{
		return mode == LAYER || needsBackdrop(mode);
	}
}
#end
