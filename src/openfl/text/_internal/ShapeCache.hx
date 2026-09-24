package openfl.text._internal;

#if !flash
import haxe.ds.IntMap;
import haxe.ds.StringMap;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.text.TextFormat)
@SuppressWarnings("checkstyle:FieldDocComment")
class ShapeCache
{
	public static var maxEntries:Int = 2048;

	private static var __shared:ShapeCache;

	private var __shortWordMap:StringMap<StringMap< #if (html5 && js) Array<Float> #else Array<GlyphPosition> #end>>;
	private var __longWordMap:StringMap<IntMap<CacheMeasurement>>;
	private var __entries:Int = 0;

	public static function shared():ShapeCache
	{
		if (__shared == null) __shared = new ShapeCache();
		return __shared;
	}

	public function new()
	{
		__shortWordMap = new StringMap();
		__longWordMap = new StringMap();
	}

	public function clear():Void
	{
		__shortWordMap = new StringMap();
		__longWordMap = new StringMap();
		__entries = 0;
	}

	private static function hashFunction(key:String):Int
	{
		var hash = 0, i, chr;
		for (i in 0...key.length)
		{
			chr = key.charCodeAt(i);
			hash = ((hash << 5) - hash) + chr;
			hash |= 0;
		}
		return hash;
	}

	public function cache(formatRange:TextFormatRange,
			getPositions:#if (js && html5) Void->Array<Float>,
		wordKey:String = null #else TextLayout #end):#if (js && html5) Array<Float> #else Array<GlyphPosition> #end
	{
		var formatKey:String = formatRange.format.__cacheKey;
		#if (!(js && html5))
		var wordKey:String = getPositions.text;
		if (getPositions.autoHint) formatKey += "|h";
		#end
		if (wordKey.length > 15)
		{
			return __cacheLongWord(wordKey, formatKey, getPositions);
		}
		else
		{
			return __cacheShortWord(wordKey, formatKey, getPositions);
		}
	}

	private inline function __measure(getPositions:#if (js && html5) Void->Array<Float>):Array<Float> #else TextLayout):Array<GlyphPosition> #end
	{
		if (__entries >= maxEntries) clear();
		__entries++;
		return #if (js && html5) getPositions() #else getPositions.positions #end;
	}

	private function __cacheShortWord(wordKey:String, formatKey:String, getPositions:#if (js && html5) Void->Array<Float>):Array<Float> #else TextLayout):Array<GlyphPosition> #end
	{
		var formatMap = __shortWordMap.get(formatKey);
		if (formatMap != null)
		{
			var hit = formatMap.get(wordKey);
			if (hit != null) return hit;
		}
		var positions = __measure(getPositions);
		formatMap = __shortWordMap.get(formatKey);
		if (formatMap == null)
		{
			formatMap = new StringMap();
			__shortWordMap.set(formatKey, formatMap);
		}
		formatMap.set(wordKey, positions);
		return positions;
	}

	private function __cacheLongWord(wordKey:String, formatKey:String, getPositions:#if (js && html5) Void->Array<Float>):Array<Float> #else TextLayout):Array<GlyphPosition> #end
	{
		var hash = hashFunction(wordKey);
		var formatMap = __longWordMap.get(formatKey);
		if (formatMap != null)
		{
			var measurement = formatMap.get(hash);
			if (measurement != null && measurement.exists(wordKey)) return measurement.get(wordKey);
		}
		var positions = __measure(getPositions);
		formatMap = __longWordMap.get(formatKey);
		if (formatMap == null)
		{
			formatMap = new IntMap();
			__longWordMap.set(formatKey, formatMap);
		}
		var measurement = formatMap.get(hash);
		if (measurement == null)
		{
			measurement = new CacheMeasurement(wordKey, positions);
			measurement.hash = hash;
			formatMap.set(hash, measurement);
		}
		else
		{
			measurement.set(wordKey, positions);
		}
		return positions;
	}
}
#end
