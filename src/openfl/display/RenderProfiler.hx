package openfl.display;

import openfl.display3D.Context3D;

class RenderPassRecord
{
	public var target:String;
	public var scope:String;
	public var draws:Int = 0;
	public var triangles:Int = 0;
	public var shaders:Map<String, Int> = new Map();
	public var query:Dynamic = null;
	public var gpuMs:Float = -1;

	public function new(target:String, scope:String)
	{
		this.target = target;
		this.scope = scope;
	}
}

class RenderFrameRecord
{
	public var passes:Array<RenderPassRecord> = [];

	public function new() {}
}

@:access(openfl.display3D.Context3D)
class RenderProfiler
{
	static inline final TIME_ELAPSED:Int = 0x88BF;
	static inline final QUERY_RESULT:Int = 0x8866;
	static inline final QUERY_AVAILABLE:Int = 0x8867;

	public static var capturing(default, null):Bool = false;
	public static var scope:String = null;
	public static var frames(default, null):Array<RenderFrameRecord> = [];
	public static var timersAvailable(default, null):Bool = false;

	static var checked:Bool = false;
	static var frame:RenderFrameRecord = null;
	static var pass:RenderPassRecord = null;
	static var querying:Bool = false;
	static var pool:Array<Dynamic> = [];

	public static function start():Void
	{
		frames = [];
		frame = null;
		pass = null;
		capturing = true;
	}

	public static function stop(context:Context3D):Void
	{
		if (frame != null) endFrame(context);
		capturing = false;
	}

	public static function beginFrame(context:Context3D):Void
	{
		if (!capturing || context == null) return;
		checkTimers(context);
		frame = new RenderFrameRecord();
		frames.push(frame);
		openPass(context, targetName(context));
	}

	public static function endFrame(context:Context3D):Void
	{
		if (frame == null || context == null) return;
		closeQuery(context);
		pass = null;
		frame = null;
	}

	@:noCompletion public static function __bound(context:Context3D):Void
	{
		if (frame == null) return;
		openPass(context, targetName(context));
	}

	@:noCompletion public static function __drawn(context:Context3D, indices:Int):Void
	{
		if (pass == null) return;
		pass.draws++;
		pass.triangles += Std.int(indices / 3);
		final shader = context.__state.shader;
		final name = shader == null ? "none" : shortName(shader);
		pass.shaders.set(name, (pass.shaders.exists(name) ? pass.shaders.get(name) : 0) + 1);
	}

	public static function collect(context:Context3D):Bool
	{
		if (context == null || !timersAvailable) return true;
		final gl = context.__context.gles3;
		var ready = true;
		for (f in frames)
			for (p in f.passes)
			{
				if (p.query == null) continue;
				if (gl.getQueryParameter(p.query, QUERY_AVAILABLE) == false)
				{
					ready = false;
					continue;
				}
				final ns:Float = gl.getQueryParameter(p.query, QUERY_RESULT);
				p.gpuMs = ns / 1000000;
				pool.push(p.query);
				p.query = null;
			}
		return ready;
	}

	static function openPass(context:Context3D, target:String):Void
	{
		closeQuery(context);
		pass = new RenderPassRecord(target, scope);
		frame.passes.push(pass);
		if (!timersAvailable) return;
		final gl = context.__context.gles3;
		pass.query = pool.length > 0 ? pool.pop() : gl.createQuery();
		gl.beginQuery(TIME_ELAPSED, pass.query);
		querying = true;
	}

	static function closeQuery(context:Context3D):Void
	{
		if (!querying) return;
		querying = false;
		context.__context.gles3.endQuery(TIME_ELAPSED);
	}

	static function checkTimers(context:Context3D):Void
	{
		if (checked) return;
		checked = true;
		final list:Array<String> = context.gl.getSupportedExtensions();
		timersAvailable = context.__context.gles3 != null && list != null && (list.indexOf("EXT_disjoint_timer_query") >= 0 || list.indexOf("GL_EXT_disjoint_timer_query") >= 0);
	}

	static function targetName(context:Context3D):String
	{
		final target = context.__state.renderToTexture;
		return target == null ? "screen" : @:privateAccess target.__width + "x" + @:privateAccess target.__height;
	}

	static function shortName(value:Dynamic):String
	{
		final name = Type.getClassName(Type.getClass(value));
		return name == null ? "?" : name.substr(name.lastIndexOf(".") + 1);
	}
}
