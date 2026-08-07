package openfl.display._internal;

#if !flash
import openfl.display3D.VertexBuffer3D;
import openfl.utils._internal.Float32Array;
import openfl.utils._internal.UInt16Array;

/**
	The one place vertex geometry is accumulated and handed to the GPU.

	Every renderer that streams quads - shapes, tiles, glyphs - needs the same two things: a CPU
	array that grows as geometry is appended, and an upload that touches only the range actually
	written. Those were previously written out separately in `Context3DBuffer`,
	`Context3DGraphics` and `Context3DTilemap`, which is why the growth policy differed between
	them and why fixing it once never fixed it everywhere.

	The growth policy is deliberately over-allocating: a buffer that needs to grow grows by half
	again, not to the exact size asked for. A frame that draws slightly more geometry than any
	previous frame then costs one reallocation rather than one per appended element, which is what
	makes it safe to size the buffer lazily while filling it instead of walking the scene twice to
	count first.
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
class GeometryBatch
{
	/**
		Returns a `Float32Array` of at least `length` floats, preserving the contents of `current`.

		Returns `current` untouched when it is already large enough, so this is cheap to call on
		every appended element.
	**/
	public static function growFloats(current:Float32Array, length:Int):Float32Array
	{
		#if lime
		if (current == null) return new Float32Array(length);
		if (length <= current.length) return current;

		var newLength = (current.length * 3) >> 1;
		if (newLength < length) newLength = length;

		var result = new Float32Array(newLength);
		result.set(current);

		return result;
		#else
		return current;
		#end
	}

	/**
		The `UInt16Array` equivalent of `growFloats`, for index data.
	**/
	public static function growIndices(current:UInt16Array, length:Int):UInt16Array
	{
		#if lime
		if (current == null) return new UInt16Array(length);
		if (length <= current.length) return current;

		var newLength = (current.length * 3) >> 1;
		if (newLength < length) newLength = length;

		var result = new UInt16Array(newLength);
		result.set(current);

		return result;
		#else
		return current;
		#end
	}

	/**
		Uploads `usedLength` floats of `data` to `vertexBuffer`.

		Because the backing array is high-watermark sized and never shrinks, uploading all of it
		would send whatever the busiest frame so far needed, every frame. Passing a `usedLength`
		shorter than the array uploads just that prefix.
	**/
	public static function upload(vertexBuffer:VertexBuffer3D, data:Float32Array, usedLength:Int):Void
	{
		#if lime
		if (vertexBuffer == null || data == null) return;

		if (usedLength > 0 && usedLength < data.length)
		{
			vertexBuffer.uploadFromTypedArray(data.subarray(0, usedLength));
		}
		else
		{
			vertexBuffer.uploadFromTypedArray(data);
		}
		#end
	}
}
#end
