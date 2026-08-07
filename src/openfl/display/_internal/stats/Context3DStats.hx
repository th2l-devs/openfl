package openfl.display._internal.stats;

import haxe.ds.IntMap;

#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@SuppressWarnings("checkstyle:FieldDocComment")
class Context3DStats
{
	private static var drawCallsCounters:IntMap<DrawCallCounter> = [
		DrawCallContext.STAGE => new DrawCallCounter(),
		DrawCallContext.STAGE3D => new DrawCallCounter()
	];

	public static function incrementDrawCall(context:DrawCallContext):Void
	{
		__getCounter(context).increment();
	}

	public static function resetDrawCalls():Void
	{
		for (dcCounter in drawCallsCounters)
		{
			dcCounter.reset();
		}
	}

	public static function totalDrawCalls():Int
	{
		var total = 0;
		for (dcCounter in drawCallsCounters)
		{
			total += dcCounter.currentDrawCallsNum;
		}

		return total;
	}

	public static function contextDrawCalls(context:DrawCallContext):Int
	{
		return __getCounter(context).currentDrawCallsNum;
	}

	/**
		Returns the counter for `context`, creating it on first use. `drawCallsCounters` is
		initialized with a hardcoded key per `DrawCallContext` value, so a direct `get()` would
		return null for any value added to the enum later.
	**/
	private static function __getCounter(context:DrawCallContext):DrawCallCounter
	{
		var counter = drawCallsCounters.get(context);

		if (counter == null)
		{
			counter = new DrawCallCounter();
			drawCallsCounters.set(context, counter);
		}

		return counter;
	}
}
