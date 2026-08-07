package openfl.display._internal;

#if !flash
import openfl.display.BlendMode;
import openfl.display.OpenGLRenderer;
import openfl.display3D.Context3D;
#if lime
import lime.graphics.WebGLRenderContext;
#end

/**
	The contract a render pass gets instead of the whole renderer.

	`Context3D` already keeps a diffed model of the GL state and only emits the calls needed to
	move the driver from its current configuration to the requested one - that part works and is
	not being replaced. What was missing is a *boundary*: every `Context3D*` class is marked
	`@:access(openfl.display.OpenGLRenderer)` and reaches straight into the renderer's private
	fields, so there is no way to add, replace or reorder a pass without knowing the renderer's
	internals.

	`GLDevice` is that boundary. A pass receives one of these rather than an `OpenGLRenderer`, and
	goes through it for GL state and for the shared geometry batcher.

	The boundary is being introduced ahead of the passes that will live behind it: `renderer` is
	still exposed, because the passes registered today are thin wrappers over the existing
	`Context3D*` statics, which take an `OpenGLRenderer`. Each pass drops that dependency as it is
	migrated; when the last one does, `renderer` goes away and the `@:access` declarations with it.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.display.OpenGLRenderer)
@:access(openfl.display3D.Context3D)
@SuppressWarnings("checkstyle:FieldDocComment")
class GLDevice
{
	/**
		The rendering context. All GL state changes go through it, so they are diffed against the
		state already set rather than issued unconditionally.
	**/
	public var context(default, null):Context3D;

	/**
		The raw GL context, for the few operations `Context3D` does not model.
	**/
	@SuppressWarnings("checkstyle:Dynamic")
	public var gl(default, null):#if lime WebGLRenderContext #else Dynamic #end;

	/**
		The renderer this device belongs to.

		Transitional - see the class documentation. New pass code should take what it needs from
		`context` and the `GLDevice` methods rather than reaching through here.
	**/
	public var renderer(default, null):OpenGLRenderer;

	public function new(renderer:OpenGLRenderer)
	{
		this.renderer = renderer;
		this.context = renderer.__context3D;
		this.gl = renderer.gl;
	}

	/**
		Whether this device draws into an isolated transparency group rather than into the scene.

		`ALPHA` and `ERASE` are only meaningful when it does - see `BlendModeSupport`.
	**/
	public var isolatedGroup(get, never):Bool;

	/**
		Sets the blend state, if it is not already what was asked for.
	**/
	public function setBlendMode(value:BlendMode):Void
	{
		renderer.__setBlendMode(value);
	}

	/**
		Re-reads the renderer's context, after the renderer has been pointed at a different one.
	**/
	public function invalidate():Void
	{
		context = renderer.__context3D;
		gl = renderer.gl;
	}

	@:noCompletion private function get_isolatedGroup():Bool
	{
		return renderer.__isolatedGroup;
	}
}
#end
