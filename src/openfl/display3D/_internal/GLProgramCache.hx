package openfl.display3D._internal;

#if (lime && sys && lime_cffi && !macro)
import haxe.crypto.Md5;
import haxe.io.Bytes;
import lime.graphics.WebGLRenderContext;
import lime.graphics.opengl.GLProgramBinary;
import lime.system.DiskCache;

class GLProgramCache
{
	public static var enabled:Bool = true;
	public static var hits(default, null):Int = 0;
	public static var misses(default, null):Int = 0;

	private static inline var VERSION:Int = 1;
	private static inline var KIND:String = "shaders";
	private static var checked:Bool = false;
	private static var usable:Bool = false;
	private static var driver:String = "";

	private static function ready(gl:WebGLRenderContext):Bool
	{
		if (!enabled) return false;
		if (checked) return usable;
		checked = true;
		try
		{
			if (!GLProgramBinary.ready()) return false;
			driver = VERSION + "|" + gl.getParameter(gl.VENDOR) + "|" + gl.getParameter(gl.RENDERER) + "|" + gl.getParameter(gl.VERSION);
			DiskCache.removeLegacy("shadercache");
			usable = true;
		}
		catch (_:Dynamic)
		{
			usable = false;
		}
		return usable;
	}

	private static inline function keyOf(vertex:String, fragment:String):String
	{
		return Md5.encode(driver + "\x01" + vertex + "\x01" + fragment) + ".bin";
	}

	public static function load(gl:WebGLRenderContext, vertex:String, fragment:String):Dynamic
	{
		if (!ready(gl)) return null;
		final key = keyOf(vertex, fragment);
		try
		{
			final file = DiskCache.get(KIND, key);
			if (file == null)
			{
				misses++;
				return null;
			}
			if (file.length > 4)
			{
				final program = gl.createProgram();
				if (GLProgramBinary.write(cast program, file.getInt32(0), file.sub(4, file.length - 4)))
				{
					hits++;
					return program;
				}
				gl.deleteProgram(program);
			}
			DiskCache.remove(KIND, key);
		}
		catch (_:Dynamic) {}
		misses++;
		return null;
	}

	public static function prepare(gl:WebGLRenderContext, program:Dynamic):Void
	{
		if (ready(gl)) GLProgramBinary.allowRead(cast program);
	}

	public static function store(gl:WebGLRenderContext, program:Dynamic, vertex:String, fragment:String):Void
	{
		if (!ready(gl)) return;
		try
		{
			final data = Bytes.alloc(0);
			final format = GLProgramBinary.read(cast program, data);
			if (format == 0 || data.length == 0) return;
			final out = Bytes.alloc(data.length + 4);
			out.setInt32(0, format);
			out.blit(4, data, 0, data.length);
			DiskCache.put(KIND, keyOf(vertex, fragment), out);
		}
		catch (_:Dynamic) {}
	}
}
#end
