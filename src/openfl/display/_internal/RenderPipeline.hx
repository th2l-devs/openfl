package openfl.display._internal;

#if !flash
import openfl.display.IBitmapDrawable;
import openfl.display._internal.Context3DRenderPasses;

/**
	The ordered set of `IRenderPass` instances a renderer draws through, and the dispatch onto
	them.

	Dispatch stays a lookup on `__drawableType` - that was never the problem, and turning it into
	anything cleverer would be optimising the wrong thing. What changes is what sits at the end of
	the lookup: a registered pass rather than a hardcoded static call, so a pass can be swapped
	without touching the renderer.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.IBitmapDrawable)
@SuppressWarnings("checkstyle:FieldDocComment")
class RenderPipeline
{
	@:noCompletion private var __passes:Array<IRenderPass>;

	// Indexed by IBitmapDrawableType, which is an enum abstract over Int
	@:noCompletion private var __byType:Array<IRenderPass>;

	public function new()
	{
		__passes = [];
		__byType = [];

		register(new BitmapDataPass());
		register(new ObjectPass());
		register(new BitmapPass());
		register(new TextPass());
		register(new VideoPass());
		register(new TilemapPass());
	}

	/**
		Adds `pass`, claiming every drawable type it accepts.

		A later registration wins, which is how a pass is replaced: register the replacement and
		it takes over the types it accepts.
	**/
	public function register(pass:IRenderPass):Void
	{
		if (pass == null) return;

		if (__passes.indexOf(pass) == -1) __passes.push(pass);

		for (type in 0...__TYPE_COUNT)
		{
			if (pass.accepts(cast type)) __byType[type] = pass;
		}
	}

	/**
		The pass responsible for `type`, or `null` if the type is not drawn by this renderer.
	**/
	public inline function getPass(type:IBitmapDrawableType):IRenderPass
	{
		return __byType[cast type];
	}

	/**
		Draws `drawable` through whichever pass claims its type.
	**/
	public function execute(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		if (drawable == null) return;

		var pass = __byType[cast drawable.__drawableType];
		if (pass != null) pass.execute(drawable, device);
	}

	/**
		Draws `drawable` as a stencil mask through whichever pass claims its type.
	**/
	public function executeMask(drawable:IBitmapDrawable, device:GLDevice):Void
	{
		if (drawable == null) return;

		var pass = __byType[cast drawable.__drawableType];
		if (pass != null) pass.executeMask(drawable, device);
	}

	/**
		Opens the frame on every registered pass.
	**/
	public function begin(device:GLDevice):Void
	{
		for (pass in __passes)
		{
			pass.begin(device);
		}
	}

	/**
		Closes the frame on every registered pass, flushing anything still accumulated.
	**/
	public function end(device:GLDevice):Void
	{
		for (pass in __passes)
		{
			pass.end(device);
		}
	}

	// One past the highest IBitmapDrawableType value
	@:noCompletion private static inline var __TYPE_COUNT:Int = 11;
}
#end
