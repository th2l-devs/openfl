package openfl.media;

#if !flash
import openfl.events.Event;
import openfl.events.EventDispatcher;
#if lime
import lime.media.AudioSource;
import lime.utils.UInt8Array;
#end
#if (js && html5)
import openfl.events.SampleDataEvent;
import js.html.audio.AudioProcessingEvent;
import js.html.audio.ScriptProcessorNode;
#end
#if lime_openal
import openfl.events.SampleDataEvent;
import openfl.utils.ByteArray;
import lime.media.openal.AL;
import lime.media.openal.ALBuffer;
import lime.media.openal.ALSource;
import lime.utils.ArrayBufferView;
import lime.utils.Int16Array;
#end

/**
	The SoundChannel class controls a sound in an application. Every sound is
	assigned to a sound channel, and the application can have multiple sound
	channels that are mixed together. The SoundChannel class contains a
	`stop()` method, properties for monitoring the amplitude
	(volume) of the channel, and a property for assigning a SoundTransform
	object to the channel.

	@event soundComplete Dispatched when a sound has finished playing.

	@see [Playing sounds](https://books.openfl.org/openfl-developers-guide/working-with-sound/playing-sounds.html)
	@see `openfl.media.Sound`
**/
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(openfl.events.SampleDataEvent)
@:access(openfl.media.Sound)
@:access(openfl.media.SoundMixer)
@:final @:keep class SoundChannel extends EventDispatcher
{
	// Level metering. Flash reports an instantaneous peak, but mastered music is limited
	// so heavily that a peak reads near full scale almost continuously and barely moves.
	// Measuring RMS over a short window instead tracks perceived loudness, and smoothing
	// it keeps the value steady between frames.
	@:noCompletion private static inline var LEVEL_WINDOW_MS:Float = 20;
	@:noCompletion private static inline var LEVEL_ATTACK_MS:Float = 15;
	@:noCompletion private static inline var LEVEL_DECAY_MS:Float = 180;

	// Beyond this gap the level is adopted outright rather than smoothed, so seeking,
	// looping, or a long hitch cannot drag a stale level along behind it
	@:noCompletion private static inline var LEVEL_RESET_MS:Float = 250;

	// Power of two so the FFT needs no padding. 1024 samples is ~23ms at 44.1kHz, matching
	// the same order of magnitude as LEVEL_WINDOW_MS - fine time resolution for beat-reactive
	// visuals while still giving ~43Hz per bin of frequency resolution.
	@:noCompletion private static inline var SPECTRUM_FFT_SIZE:Int = 1024;
	@:noCompletion private static inline var SPECTRUM_MIN_HZ:Float = 20;
	@:noCompletion private static inline var SPECTRUM_MAX_HZ:Float = 16000;

	/**
		The current amplitude (volume) of the left channel, from 0 (silent) to 1
		(full amplitude).

		Measured as the smoothed RMS level of the audio around the current playback
		position, scaled by the volume and panning actually applied to the channel.
		Streamed audio keeps no samples in memory and reports 0.
	**/
	public var leftPeak(get, never):Float;

	/**
		The left channel's source signal level, from 0 (silent) to 1 (full amplitude).

		The same smoothed RMS measurement as `leftPeak`, but taken BEFORE volume and
		panning are applied: it describes the audio content itself, so it does not change
		when the channel, mixer or application volume changes. Use this for visualizers
		and beat detection; use `leftPeak` for what is actually audible.
		Streamed audio keeps no samples in memory and reports 0.
	**/
	public var leftLevel(get, never):Float;

	/**
		When the sound is playing, the `position` property indicates in
		milliseconds the current point that is being played in the sound file.
		When the sound is stopped or paused, the `position` property
		indicates the last point that was played in the sound file.

		A common use case is to save the value of the `position`
		property when the sound is stopped. You can resume the sound later by
		restarting it from that saved position.

		If the sound is looped, `position` is reset to 0 at the
		beginning of each loop.
	**/
	public var position(get, set):Float;

	/**
		The current amplitude (volume) of the right channel, from 0 (silent) to 1
		(full amplitude).

		Measured as the smoothed RMS level of the audio around the current playback
		position, scaled by the volume and panning actually applied to the channel.
		Streamed audio keeps no samples in memory and reports 0.
	**/
	public var rightPeak(get, never):Float;

	/**
		The right channel's source signal level, from 0 (silent) to 1 (full amplitude).
		See `leftLevel`.
	**/
	public var rightLevel(get, never):Float;

	/**
		The SoundTransform object assigned to the sound channel. A SoundTransform
		object includes properties for setting volume, panning, left speaker
		assignment, and right speaker assignment.
	**/
	public var soundTransform(get, set):SoundTransform;

	@:noCompletion private var __sound:Sound;
	@:noCompletion private var __isValid:Bool;
	@:noCompletion private var __leftLevel:Float;
	@:noCompletion private var __leftPeak:Float;
	@:noCompletion private var __peakTime:Float;
	@:noCompletion private var __rightLevel:Float;
	@:noCompletion private var __rightPeak:Float;
	@:noCompletion private var __soundTransform:SoundTransform;
	@:noCompletion private var __spectrum:Array<Float>;
	@:noCompletion private var __spectrumBands:Int = 0;
	@:noCompletion private var __spectrumTime:Float = -1;
	#if lime
	@:noCompletion private var __audioSource:AudioSource;
	#end

	#if (js && html5)
	private var __sampleDataEvent:SampleDataEvent;
	private var __processor:ScriptProcessorNode;
	private var __firstRun:Bool = true;
	#end

	#if lime_openal
	private var __sampleDataEvent:SampleDataEvent;
	private var __alSource:ALSource;
	private var __outputBuffer:ByteArray;
	private var __bufferView:ArrayBufferView;
	private var __alBuffers:Array<ALBuffer>;
	private var __numberOfBuffers:Int = 3;
	private var __emptyBuffers:Array<ALBuffer>;
	#end

	#if openfljs
	@:noCompletion private static function __init__()
	{
		untyped Object.defineProperties(SoundChannel.prototype, {
			"leftPeak": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_leftPeak (); }")
			},
			"rightPeak": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_rightPeak (); }")
			},
			"position": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_position (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_position (v); }")
			},
			"soundTransform": {
				get: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function () { return this.get_soundTransform (); }"),
				set: untyped #if haxe4 js.Syntax.code #else __js__ #end ("function (v) { return this.set_soundTransform (v); }")
			},
		});
	}
	#end

	@:noCompletion private function new(sound:Sound, audioSource:#if lime AudioSource #else Dynamic #end = null, soundTransform:SoundTransform = null):Void
	{
		super(this);

		__sound = sound;

		__leftLevel = 0;
		__rightLevel = 0;
		__leftPeak = 0;
		__rightPeak = 0;
		__peakTime = -1;

		if (soundTransform != null)
		{
			__soundTransform = soundTransform;
		}
		else
		{
			__soundTransform = new SoundTransform();
		}

		__initAudioSource(audioSource);

		SoundMixer.__registerSoundChannel(this);
	}

	/**
		Stops the sound playing in the channel.

		@see [Playing sounds](https://books.openfl.org/openfl-developers-guide/working-with-sound/playing-sounds.html)
	**/
	public function stop():Void
	{
		SoundMixer.__unregisterSoundChannel(this);

		if (!__isValid) return;

		#if (js && html5)
		if (__processor != null)
		{
			__processor.disconnect();
			__processor.onaudioprocess = null;
			__processor = null;
		}
		#end

		#if lime_openal
		if (__alSource != null)
		{
			lime.app.Application.current.onUpdate.remove(watchBuffers);
			var alAudioContext = __sound.__alAudioContext;
			alAudioContext.sourceStop(__alSource);
			alAudioContext.deleteSource(__alSource);
			alAudioContext.deleteBuffers(__alBuffers);
			__emptyBuffers = null;
			__alSource = null;
		}
		#end

		#if lime
		__audioSource.stop();
		#end
		__dispose();
	}

	@:noCompletion private function __dispose():Void
	{
		if (!__isValid) return;

		#if lime
		__audioSource.onComplete.remove(audioSource_onComplete);
		__audioSource.dispose();
		__audioSource = null;
		#end
		__isValid = false;
	}

	@:noCompletion private function __startSampleData():Void
	{
		#if (js && html5)
		var webAudioContext = __sound.__webAudioContext;
		if (webAudioContext != null)
		{
			__sampleDataEvent = new SampleDataEvent(SampleDataEvent.SAMPLE_DATA);
			__sound.dispatchEvent(__sampleDataEvent);
			var bufferSize = __sampleDataEvent.getBufferSize();
			if (bufferSize == 0)
			{
				// ensure that listeners can be added to the SoundChannel
				// before dispatching this event
				openfl.Lib.setTimeout(function():Void
				{
					stop();
					dispatchEvent(new Event(Event.SOUND_COMPLETE));
				}, 1);
			}
			else
			{
				__processor = webAudioContext.createScriptProcessor(bufferSize, 0, 2);
				__processor.connect(webAudioContext.destination);
				__processor.onaudioprocess = onSample;
				#if (haxe_ver >= 4.2)
				webAudioContext.resume();
				#else
				Reflect.callMethod(webAudioContext, Reflect.field(webAudioContext, "resume"), []);
				#end
			}
		}
		#end
		#if lime_openal
		var alAudioContext = __sound.__alAudioContext;
		if (alAudioContext != null)
		{
			__sampleDataEvent = new SampleDataEvent(SampleDataEvent.SAMPLE_DATA);
			__sound.dispatchEvent(__sampleDataEvent);
			var bufferSize = __sampleDataEvent.getBufferSize();
			if (bufferSize == 0)
			{
				// ensure that listeners can be added to the SoundChannel
				// before dispatching this event
				openfl.Lib.setTimeout(function():Void
				{
					stop();
					dispatchEvent(new Event(Event.SOUND_COMPLETE));
				}, 1);
			}
			else
			{
				bufferSize = 0;
				__alSource = alAudioContext.createSource();
				alAudioContext.sourcef(__alSource, AL.GAIN, 1);
				alAudioContext.source3f(__alSource, AL.POSITION, 0, 0, 0);
				alAudioContext.sourcef(__alSource, AL.PITCH, 1.0);

				__alBuffers = alAudioContext.genBuffers(__numberOfBuffers);
				__outputBuffer = new ByteArray();
				__bufferView = new lime.utils.Int16Array(__outputBuffer);

				for (a in 0...__numberOfBuffers)
				{
					if (bufferSize == 0)
					{
						bufferSize = __sampleDataEvent.getBufferSize();
						__sampleDataEvent.getSamples(__outputBuffer);
						alAudioContext.bufferData(__alBuffers[a], AL.FORMAT_STEREO16, __bufferView, bufferSize * 4, 44100);
					}
					else
					{
						__sound.dispatchEvent(__sampleDataEvent);
						__sampleDataEvent.getSamples(__outputBuffer);
						alAudioContext.bufferData(__alBuffers[a], AL.FORMAT_STEREO16, __bufferView, bufferSize * 4, 44100);
					}
				}

				alAudioContext.sourceQueueBuffers(__alSource, __numberOfBuffers, __alBuffers);

				alAudioContext.sourcePlay(__alSource);
				lime.app.Application.current.onUpdate.add(watchBuffers);
			}
		}
		#end
	}

	@:noCompletion private function __updateTransform():Void
	{
		this.soundTransform = soundTransform;
	}

	/**
		Measures the output level of each channel from the decoded waveform around the
		current playback position.

		Flash meters its mixed output directly, but OpenAL exposes no equivalent, so the
		level is read back from the source buffer instead. Streamed audio holds no PCM in
		memory and therefore reports no level.
	**/
	@:noCompletion private function __updatePeaks():Void
	{
		#if lime
		if (!__isValid || __sound == null)
		{
			__leftLevel = 0;
			__rightLevel = 0;
			__leftPeak = 0;
			__rightPeak = 0;
			__peakTime = -1;
			return;
		}

		var buffer = __sound.__buffer;
		if (buffer == null || buffer.data == null || buffer.data.length == 0) return;

		var sampleRate = buffer.sampleRate;
		var channels = buffer.channels;
		var bitsPerSample = buffer.bitsPerSample;

		if (sampleRate <= 0 || channels <= 0) return;

		if (bitsPerSample != 8 && bitsPerSample != 16)
		{
			// Lime decodes to 8 or 16 bit, so anything else is an unknown layout that
			// could be integer or float. Report nothing rather than a stale level.
			__leftLevel = 0;
			__rightLevel = 0;
			__leftPeak = 0;
			__rightPeak = 0;
			return;
		}

		// Both channels are read once per frame, so only measure when playback has moved on
		var time = position;
		if (time == __peakTime) return;

		var elapsed = time - __peakTime;
		var continuous = (__peakTime >= 0 && elapsed > 0 && elapsed < LEVEL_RESET_MS);
		__peakTime = time;

		var data = buffer.data;
		var bytesPerSample = bitsPerSample >> 3;
		var frameSize = bytesPerSample * channels;
		var totalFrames = Std.int(data.length / frameSize);

		var windowFrames = Std.int((LEVEL_WINDOW_MS / 1000) * sampleRate);
		if (windowFrames < 1) windowFrames = 1;

		// Center the window on the playhead so the level describes what is being heard
		// now, rather than audio that has not reached the speakers yet
		var start = Std.int((time / 1000) * sampleRate) - (windowFrames >> 1);
		if (start < 0) start = 0;

		var end = start + windowFrames;
		if (end > totalFrames) end = totalFrames;

		var count = end - start;

		if (count <= 0)
		{
			__leftLevel = 0;
			__rightLevel = 0;
			__leftPeak = 0;
			__rightPeak = 0;
			return;
		}

		var leftSum = 0.0;
		var rightSum = 0.0;
		var offset = start * frameSize;

		for (i in 0...count)
		{
			var sampleOffset = offset + (i * frameSize);

			var l = __readSample(data, sampleOffset, bitsPerSample);
			var r = (channels > 1) ? __readSample(data, sampleOffset + bytesPerSample, bitsPerSample) : l;

			leftSum += l * l;
			rightSum += r * r;
		}

		var left = Math.sqrt(leftSum / count);
		var right = Math.sqrt(rightSum / count);

		// Smooth the SOURCE level, before any gain: leftLevel/rightLevel describe the audio
		// content itself, so they stay put when the channel, mixer or application volume
		// changes - and a gain change can never be smeared into the measurement by the
		// attack/decay filter.
		if (continuous)
		{
			__leftLevel = __smoothLevel(__leftLevel, left, elapsed);
			__rightLevel = __smoothLevel(__rightLevel, right, elapsed);
		}
		else
		{
			// Starting, seeking or looping: adopt the level rather than sliding to it
			__leftLevel = left;
			__rightLevel = right;
		}

		// The audible (Flash-compatible) peaks derive from the smoothed source level.
		// Mirror the gain that set_soundTransform actually hands to the audio source,
		// including the global mixer, so the peak tracks what is audible.
		var volume = SoundMixer.__soundTransform.volume * __soundTransform.volume;

		var pan = SoundMixer.__soundTransform.pan + __soundTransform.pan;
		if (pan < -1) pan = -1;
		if (pan > 1) pan = 1;

		// Panning reaches the output through OpenAL's 3D positioning, which has no exact
		// closed form here, so apply Flash's own pan law as the closest description
		__leftPeak = __leftLevel * volume * (pan > 0 ? 1 - pan : 1);
		__rightPeak = __rightLevel * volume * (pan < 0 ? 1 + pan : 1);
		#end
	}

	/**
		Per-band frequency magnitudes (0..1) around the current playback position, via a
		1024-point FFT of the decoded waveform - the frequency-domain sibling of `leftLevel`.

		Bands are log-spaced from `SPECTRUM_MIN_HZ` to `SPECTRUM_MAX_HZ`, so low `bands` counts
		read like a bass/mid/treble split rather than wasting resolution on the sub-bass end.
		Smoothed with the same attack/decay as `leftLevel` so it reads steadily frame to frame.
		Streamed audio keeps no samples in memory and reports all zeroes, same as `leftLevel`.

		@param bands Number of log-spaced bands to return, clamped to 1-128.
	**/
	public function getSpectrum(bands:Int = 16):Array<Float>
	{
		if (bands < 1) bands = 1;
		if (bands > 128) bands = 128;

		#if lime
		if (!__isValid || __sound == null) return __zeroSpectrum(bands);

		var buffer = __sound.__buffer;
		if (buffer == null || buffer.data == null || buffer.data.length == 0) return __zeroSpectrum(bands);

		var sampleRate = buffer.sampleRate;
		var channels = buffer.channels;
		var bitsPerSample = buffer.bitsPerSample;

		if (sampleRate <= 0 || channels <= 0) return __zeroSpectrum(bands);

		if (bitsPerSample != 8 && bitsPerSample != 16)
		{
			// Same unknown-layout guard as __updatePeaks - report nothing rather than garbage
			return __zeroSpectrum(bands);
		}

		var time = position;

		// Reuse the last result if nothing has moved and the band count hasn't changed, same
		// per-frame gate __updatePeaks uses for leftLevel/rightLevel
		if (__spectrum != null && bands == __spectrumBands && time == __spectrumTime)
			return __spectrum;

		var data = buffer.data;
		var bytesPerSample = bitsPerSample >> 3;
		var frameSize = bytesPerSample * channels;
		var totalFrames = Std.int(data.length / frameSize);

		var fftSize = SPECTRUM_FFT_SIZE;
		var start = Std.int((time / 1000) * sampleRate) - (fftSize >> 1);

		var real = new Array<Float>();
		var imag = new Array<Float>();
		real.resize(fftSize);
		imag.resize(fftSize);

		for (i in 0...fftSize)
		{
			var frame = start + i;
			var sample = 0.0;

			if (frame >= 0 && frame < totalFrames)
			{
				var offset = frame * frameSize;
				var l = __readSample(data, offset, bitsPerSample);
				var r = (channels > 1) ? __readSample(data, offset + bytesPerSample, bitsPerSample) : l;
				sample = (l + r) * 0.5;
			}

			// Hann window: without it, the hard edges of this finite slice smear energy across
			// every band (spectral leakage), which would make the result look noisy/flat
			var w = 0.5 - 0.5 * Math.cos((2 * Math.PI * i) / (fftSize - 1));
			real[i] = sample * w;
			imag[i] = 0;
		}

		__fft(real, imag);

		var half = fftSize >> 1;
		var norm = 2.0 / fftSize;
		var mags = new Array<Float>();
		mags.resize(half);
		for (i in 0...half)
			mags[i] = Math.sqrt(real[i] * real[i] + imag[i] * imag[i]) * norm;

		var target = __binSpectrum(mags, sampleRate, fftSize, bands);

		if (__spectrum == null || __spectrumBands != bands)
		{
			__spectrum = target;
		}
		else
		{
			var elapsed = time - __spectrumTime;
			var continuous = (__spectrumTime >= 0 && elapsed > 0 && elapsed < LEVEL_RESET_MS);

			for (i in 0...bands)
			{
				__spectrum[i] = continuous ? __smoothLevel(__spectrum[i], target[i], elapsed) : target[i];
			}
		}

		__spectrumBands = bands;
		__spectrumTime = time;
		return __spectrum;
		#else
		return __zeroSpectrum(bands);
		#end
	}

	@:noCompletion private static function __zeroSpectrum(bands:Int):Array<Float>
	{
		var result = new Array<Float>();
		result.resize(bands);
		for (i in 0...bands) result[i] = 0.0;
		return result;
	}

	// Groups linear FFT bins into `bands` log-spaced bands - music perception is logarithmic
	// (an octave is a doubling in Hz regardless of where it starts), so linear bins would give
	// bass a handful of bands and treble hundreds of nearly-identical ones.
	@:noCompletion private static function __binSpectrum(mags:Array<Float>, sampleRate:Int, fftSize:Int, bands:Int):Array<Float>
	{
		var result = new Array<Float>();
		result.resize(bands);

		var nyquist = sampleRate * 0.5;
		var maxFreq = Math.min(nyquist, SPECTRUM_MAX_HZ);
		var logMin = Math.log(SPECTRUM_MIN_HZ);
		var logMax = Math.log(maxFreq);
		var binHz = sampleRate / fftSize;

		for (b in 0...bands)
		{
			var f0 = Math.exp(logMin + (logMax - logMin) * (b / bands));
			var f1 = Math.exp(logMin + (logMax - logMin) * ((b + 1) / bands));

			var bin0 = Std.int(f0 / binHz);
			var bin1 = Std.int(Math.max(bin0 + 1, f1 / binHz));
			if (bin1 > mags.length) bin1 = mags.length;

			var sum = 0.0;
			var count = 0;
			var i = bin0;
			while (i < bin1)
			{
				if (i >= 0 && i < mags.length)
				{
					sum += mags[i];
					count++;
				}
				i++;
			}

			result[b] = (count > 0) ? (sum / count) : 0.0;
		}

		return result;
	}

	// Iterative in-place radix-2 Cooley-Tukey FFT. `real.length` must be a power of two
	// (always SPECTRUM_FFT_SIZE here, so no runtime check).
	@:noCompletion private static function __fft(real:Array<Float>, imag:Array<Float>):Void
	{
		var n = real.length;

		var j = 0;
		for (i in 0...n)
		{
			if (i < j)
			{
				var tr = real[i]; real[i] = real[j]; real[j] = tr;
				var ti = imag[i]; imag[i] = imag[j]; imag[j] = ti;
			}

			var m = n >> 1;
			while (m >= 1 && (j & m) != 0)
			{
				j &= ~m;
				m >>= 1;
			}
			j |= m;
		}

		var len = 2;
		while (len <= n)
		{
			var ang = -2 * Math.PI / len;
			var wr = Math.cos(ang);
			var wi = Math.sin(ang);
			var half = len >> 1;
			var i = 0;

			while (i < n)
			{
				var curWr = 1.0;
				var curWi = 0.0;

				for (k in 0...half)
				{
					var evenIdx = i + k;
					var oddIdx = i + k + half;

					var tr = real[oddIdx] * curWr - imag[oddIdx] * curWi;
					var ti = real[oddIdx] * curWi + imag[oddIdx] * curWr;

					real[oddIdx] = real[evenIdx] - tr;
					imag[oddIdx] = imag[evenIdx] - ti;
					real[evenIdx] += tr;
					imag[evenIdx] += ti;

					var nwr = curWr * wr - curWi * wi;
					var nwi = curWr * wi + curWi * wr;
					curWr = nwr;
					curWi = nwi;
				}

				i += len;
			}

			len <<= 1;
		}
	}

	/**
		Moves a level toward a new measurement, rising quickly so transients register and
		falling slowly so the result reads steadily. Driven by elapsed playback time, so
		the response does not change with frame rate.
	**/
	@:noCompletion private static function __smoothLevel(current:Float, target:Float, elapsed:Float):Float
	{
		var tau = (target > current) ? LEVEL_ATTACK_MS : LEVEL_DECAY_MS;
		return current + (target - current) * (1 - Math.exp(-elapsed / tau));
	}

	#if lime
	@:noCompletion private static function __readSample(data:UInt8Array, offset:Int, bitsPerSample:Int):Float
	{
		if (bitsPerSample == 8)
		{
			// 8-bit PCM is unsigned and centered on 128
			return (data[offset] - 128) / 128.0;
		}

		var value = data[offset] | (data[offset + 1] << 8);
		if (value >= 32768) value -= 65536;
		return value / 32768.0;
	}
	#end

	@:noCompletion private function __initAudioSource(audioSource:#if lime AudioSource #else Dynamic #end):Void
	{
		#if lime
		__audioSource = audioSource;
		if (__audioSource == null)
		{
			return;
		}

		__audioSource.onComplete.add(audioSource_onComplete);
		__isValid = true;

		__audioSource.play();
		#end
	}

	// Get & Set Methods
	@:noCompletion private function get_leftPeak():Float
	{
		__updatePeaks();
		return __leftPeak;
	}

	@:noCompletion private function get_leftLevel():Float
	{
		__updatePeaks();
		return __leftLevel;
	}

	@:noCompletion private function get_rightLevel():Float
	{
		__updatePeaks();
		return __rightLevel;
	}

	@:noCompletion private function get_rightPeak():Float
	{
		__updatePeaks();
		return __rightPeak;
	}

	@:noCompletion private function get_position():Float
	{
		if (!__isValid) return 0;

		#if lime
		// Float-precision path: `currentTime` (Int ms) quantizes, which is audible drift for
		// rhythm-game seeking. `currentTimePrecise` is sample-accurate on the native backend.
		return __audioSource.currentTimePrecise + __audioSource.offset;
		#else
		return 0;
		#end
	}

	@:noCompletion private function set_position(value:Float):Float
	{
		if (!__isValid) return 0;

		#if lime
		__audioSource.currentTimePrecise = value - __audioSource.offset;
		#end
		return value;
	}

	@:noCompletion private function get_soundTransform():SoundTransform
	{
		return __soundTransform.clone();
	}

	@:noCompletion private function set_soundTransform(value:SoundTransform):SoundTransform
	{
		if (value != null)
		{
			__soundTransform.pan = value.pan;
			__soundTransform.volume = value.volume;

			var pan = SoundMixer.__soundTransform.pan + __soundTransform.pan;

			if (pan < -1) pan = -1;
			if (pan > 1) pan = 1;

			var volume = SoundMixer.__soundTransform.volume * __soundTransform.volume;

			if (__isValid)
			{
				#if lime
				__audioSource.gain = volume;

				var position = __audioSource.position;
				position.x = pan;
				position.z = -1 * Math.sqrt(1 - Math.pow(pan, 2));
				__audioSource.position = position;

				return value;
				#end
			}
		}

		return value;
	}

	// Event Handlers
	@:noCompletion private function audioSource_onComplete():Void
	{
		SoundMixer.__unregisterSoundChannel(this);

		__dispose();
		dispatchEvent(new Event(Event.SOUND_COMPLETE));
	}

	#if (js && html5)
	private function onSample(event:AudioProcessingEvent):Void
	{
		var hasSampleData = false;
		if (__firstRun)
		{
			hasSampleData = true;
			__firstRun = false;
		}
		else
		{
			__sampleDataEvent.data.length = 0;
			__sound.dispatchEvent(__sampleDataEvent);
			hasSampleData = __sampleDataEvent.data.length > 0;
		}
		if (hasSampleData)
		{
			__sampleDataEvent.getSamples(event);
		}
		else
		{
			stop();
			dispatchEvent(new Event(Event.SOUND_COMPLETE));
		}
	}
	#end

	#if lime_openal
	private function watchBuffers(i:Float):Void
	{
		var alAudioContext = __sound.__alAudioContext;
		var hasSampleData = true;

		if (alAudioContext != null)
		{
			var bufferState = alAudioContext.getSourcei(__alSource, AL.BUFFERS_PROCESSED);
			if (bufferState > 0)
			{
				__emptyBuffers = alAudioContext.sourceUnqueueBuffers(__alSource, bufferState);
				for (a in 0...__emptyBuffers.length)
				{
					__sampleDataEvent.data.length = 0;
					__sound.dispatchEvent(__sampleDataEvent);
					if (__sampleDataEvent.data.length == 0)
					{
						hasSampleData = false;
					}
					else
					{
						__sampleDataEvent.getSamples(__outputBuffer);
						alAudioContext.bufferData(__emptyBuffers[a], AL.FORMAT_STEREO16, __bufferView, __sampleDataEvent.getBufferSize() * 4,
							44100);
						alAudioContext.sourceQueueBuffer(__alSource, __emptyBuffers[a]);
					}
				}

				if (hasSampleData && alAudioContext.getSourcei(__alSource, AL.SOURCE_STATE) != AL.PLAYING)
				{
					alAudioContext.sourcePlay(__alSource);
				}
			}
		}
		if (!hasSampleData)
		{
			stop();
			dispatchEvent(new Event(Event.SOUND_COMPLETE));
		}
	}
	#end
}
#else
typedef SoundChannel = flash.media.SoundChannel;
#end
