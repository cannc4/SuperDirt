/*

CORE SYNTHDEFS FOR DIRT
(REQUIRED: CORE MODULES)

these synthdefs can be hacked at runtime, but they are absolutely necessary for tidal to work correctly.

Their name and parameter names shouldn't be changed. Parameter names can be added though.

live coding them requires that you have your SuperDirt instance in an environment variable called ~dirt.

*/

(
{
	var numChannels = ~dirt.numChannels;



	// write variants for different sample buffer sizes
	(1..SuperDirt.maxSampleNumChannels).do { |sampleNumChannels|

		var name = format("dirt_sample_%_%", sampleNumChannels, numChannels);

		SynthDef(name, { |out, bufnum, sustain = 1, begin=0, end=1, speed = 1, endSpeed = 1, pan = 0, vrate=0, vibrato=0|

			var sound, rate, phase, sawrate, numFrames;

			// playback speed
			rate = Line.kr(speed, endSpeed, sustain) * (2**SinOsc.kr(vrate,0,vibrato/12));

			// sample phase
			// BufSampleRate adjusts the rate if the sound file doesn't have the same rate as the soundcard
			//phase =  Sweep.ar(1, rate * BufSampleRate.ir(bufnum)) + (BufFrames.ir(bufnum) * begin);

			numFrames = BufFrames.ir(bufnum);
			sawrate = rate * BufSampleRate.ir(bufnum) / (absdif(begin, end) * numFrames);
			phase = (speed.sign * LFSaw.ar(sawrate, 1)).range(begin,end) * numFrames;

			sound = BufRd.ar(
				numChannels: sampleNumChannels,
				bufnum: bufnum,
				phase: phase,
				loop: 0,
				interpolation: 4 // cubic interpolation
			);

			if (sound.numChannels == 1) {
				sound = DirtPan.ar(sound, numChannels, pan);
			} {
				sound = Balance2.ar(sound[0], sound[1], pan*2-1);
				sound = DirtPan.ar(sound, numChannels, 0.5, 1, {|x| x});
			};

			Out.ar(out, sound)
		}, [\ir, \ir, \ir, \ir, \ir, \ir, \ir, \ir]).add;
	};

	// experimental sample mixing - very fragile
	SynthDef(format("dirt_sampleduo_%", numChannels), { |out, bufnum1, bufnum2, sustain = 1, begin=0, end=1, speed = 1, endSpeed = 1, pan = 0|
		var sound, sound1, sound2, p,q,rate, phase, sawrate, numFrames;
		// playback speed
		rate = Line.kr(speed, endSpeed, sustain);
		// sample phase
		// BufSampleRate adjusts the rate if the sound file doesn't have the same rate as the soundcard
		//phase =  Sweep.ar(1, rate * BufSampleRate.ir(bufnum)) + (BufFrames.ir(bufnum) * begin);
		numFrames = BufFrames.ir(bufnum1);
		sawrate = rate * BufSampleRate.ir(bufnum1) / (absdif(begin, end) * numFrames);
		phase = (speed.sign * LFSaw.ar(sawrate, 1)).range(begin,end) * numFrames;
		sound1 = BufRd.ar(
			numChannels: 1, bufnum: bufnum1, phase: phase, loop: 0, interpolation: 4 // cubic interpolation
		);
		numFrames = BufFrames.ir(bufnum2);
		//sawrate = rate * BufSampleRate.ir(bufnum2) / (absdif(begin, end) * numFrames) * (sound1*0.5+1) ; // FM mod
		sawrate = rate * BufSampleRate.ir(bufnum2) / (absdif(begin, end) * numFrames) ;
		phase = (speed.sign * LFSaw.ar(sawrate, 1)).range(begin,end) * numFrames;
		sound2 = BufRd.ar(
			numChannels: 1, bufnum: bufnum2, phase: phase, loop: 0, interpolation: 4 // cubic interpolation
		);
		p = sound1 * (2**31);
		q = sound2 * (2**31);
		sound = DirtPan.ar(bitXor(p, q) / (2**31), numChannels, pan);
		//sound = DirtPan.ar(sound2, numChannels, pan);
		Out.ar(out, sound)
	}, [\ir, \ir, \ir, \ir, \ir, \ir, \ir, \ir]).add;

	/*

	Bus Routing Monitor

	*/


	// the monitor does the mixing and zeroing of the busses for each sample grain
	// so that they can all play in one bus

	SynthDef("dirt_gate" ++ numChannels, { |out, in, sustain = 1, fadeInTime = 0.001, fadeTime = 0.001, amp = 1|
		var signal = In.ar(in, numChannels);
		 //  doneAction: 14: free surrounding group and all nodes
		var env = EnvGen.ar(Env([0, 1, 1, 0], [fadeInTime, sustain, fadeTime], \sin), levelScale: amp, doneAction: 14);
		signal = signal * env * DirtGateCutGroup.ar(fadeTime, doneAction: 14);
		OffsetOut.ar(out, signal);
		ReplaceOut.ar(in, Silent.ar(numChannels)) // clears bus signal for subsequent synths
	}, [\ir, \ir, \ir, \ir, \ir, \ir]).add;



	/*

	Effect SynthDefs
	These per-sample-effects are freed after Monitor envelope has ended

	*/

	SynthDef("dirt_vowel" ++ numChannels, { |out, resonance = 0.5, cutoff = 0|
		var voweled, signal, vowelFreqs, vowelAmps, vowelRqs;
		signal = In.ar(out, numChannels);
		vowelFreqs = \vowelFreqs.ir(1000 ! 5) * cutoff.linexp(0, 1, 1, 2);
		vowelAmps = \vowelAmps.ir(0 ! 5) * resonance.linlin(0, 1, 50, 200);
		vowelRqs = \vowelRqs.ir(0 ! 5) / resonance.linlin(0, 1, 1/10, 1/2);
		vowelFreqs = vowelFreqs.minNyquist; // limit ceiling
		voweled = BPF.ar([signal], vowelFreqs, vowelRqs, vowelAmps).sum;
		//voweled = Formlet.ar(signal, vowelFreqs, 0.005, vowelRqs, vowelAmps).sum;
		signal = XFade2.ar(signal, voweled, resonance.linlin(0, 1, -0.5, 1), 0.25);

		ReplaceOut.ar(out, signal);

	}, [\ir, \ir, \ir]).add;

	// would be nice to have some more parameters in some cases

	SynthDef("dirt_crush" ++ numChannels, { |out, crush = 4|
		var signal = In.ar(out, numChannels);
		signal = signal.round(0.5 ** (crush-1));
		ReplaceOut.ar(out, signal)
	}, [\ir, \ir]).add;


	SynthDef("dirt_coarse" ++ numChannels, { |out, coarse = 0, bandq = 10|
		var signal = In.ar(out, numChannels);
		signal = Latch.ar(signal, Impulse.ar(SampleRate.ir / coarse));
		ReplaceOut.ar(out, signal)
	}, [\ir, \ir, \ir]).add;

	SynthDef("dirt_hpf" ++ numChannels, { |out, hcutoff = 440, hresonance = 0|
		var signal = In.ar(out, numChannels);
		signal = RHPF.ar(signal, hcutoff, hresonance.linexp(0, 1, 1, 0.001));
		ReplaceOut.ar(out, signal)
	}, [\ir, \ir, \ir]).add;

	SynthDef("dirt_bpf" ++ numChannels, { |out, bandqf = 440, bandq = 10|
		var signal = In.ar(out, numChannels);
		bandq = max(1, bandq);  // limit quality, avoid division by zero
		bandqf = max(20, bandqf); // limit lower end, avoid blow up
		signal = BPF.ar(signal, bandqf, 1/bandq) * max(bandq, 1.0);
		ReplaceOut.ar(out, signal)
	}, [\ir, \ir, \ir]).add;

	SynthDef("dirt_shape" ++ numChannels, { |out, shape = 0|
		var signal = In.ar(out, numChannels), amp = 1;
		shape = min(shape, 1.0 - 1e-16); // avoid division by zero
		amp = 1.0 - (0.15 * shape / (shape + 2.0)) * amp; // optional gain comp
		shape = (2.0 * shape) / (1.0 - shape);

		signal = (1 + shape) * signal / (1 + (shape * abs(signal)));
		ReplaceOut.ar(out, signal * amp)
	}, [\ir, \ir]).add;

	SynthDef("dirt_lpf" ++ numChannels, { |out, cutoff = 440, resonance = 0|
		var signal = In.ar(out, numChannels);
		signal = RLPF.ar(signal, cutoff, resonance.linexp(0, 1, 1, 0.001));
		ReplaceOut.ar(out, signal)
	}, [\ir, \ir, \ir]).add;

	SynthDef("dirt_envelope" ++ numChannels, { |out, attack = 0, hold = 0, release = inf |
		var signal = In.ar(out, numChannels);
		signal = signal * EnvGen.ar(Env.linen(attack, hold, release, 1, -3));
		ReplaceOut.ar(out, signal);
	}, [\ir, \ir, \ir, \ir]).add;


	// global synth defs: these synths run in each DirtOrbit and are only released when it is stopped
	// when you change them, to update them, hit cmd-period (i.e. stop the synths on the server) once.
	// they'll come back automatically

	if(\SwitchDelay.asClass.notNil) {

		SynthDef("dirt_delay" ++ numChannels, { |dryBus, effectBus, gate = 1, delaytime, delayfeedback, delayAmp = 1, lock = 0, cps = 1|
			var signal;
			var input = In.ar(dryBus, numChannels);
			var maxDelayTime = 4;

			delayfeedback = delayfeedback.max(0);
			delaytime = delaytime * if(lock, reciprocal(cps), 1);
			delaytime = delaytime.clip(0, maxDelayTime); // just to be sure
			// from sc3-plugins
			signal = \SwitchDelay.asClass.ar(input, 1, 1, delaytime, delayfeedback, maxDelayTime);

			DetectSilence.ar(signal, time:1, doneAction: 1);
			// doesn't work properly. We don't really know when it's not used anymore.
			// this would have to be an explicit signal from sclang

			signal = signal * EnvGen.kr(Env.asr, gate, doneAction:2);
			signal = signal * delayAmp.lag(0.01);

			DirtPause.ar(signal, graceTime:4);

			Out.ar(effectBus, signal);

		}, [\ir, \ir]).add;
	} {
		"\n\n ---- SC3-Plugins not found. This is not a problem."
		"Note that we are using a comb delay, which may not sound the same as SwitchDelay from the plugins".postln;

		SynthDef("dirt_delay" ++ numChannels, { |dryBus, effectBus, gate = 1, delaytime, delayfeedback, delayAmp = 1, lock = 0, cps = 1|
			var signal = In.ar(dryBus, numChannels);
			var maxDelayTime = 4;
			var decayTime;

			delayfeedback = delayfeedback.clip(0, 0.99);
			delaytime = delaytime * if(lock, reciprocal(cps), 1);
			delaytime = delaytime.clip(0, maxDelayTime); // just to be sure
			decayTime = log2(-60.dbamp) / log2(delayfeedback) * delaytime;
			decayTime = decayTime.clip(0, 20);

			signal = CombL.ar(signal, maxDelayTime, delaytime.lag(1), decayTime);

			signal = LeakDC.ar(signal) * delayAmp.lag(0.01) * EnvGen.kr(Env.asr, gate, doneAction:2);

			DirtPause.ar(signal, graceTime:4);

			Out.ar(effectBus, signal);
		}, [\ir, \ir]).add;
	};

	SynthDef("dirt_tape" ++ numChannels, { |dryBus, effectBus, gate = 1, tapeAmp=1, taped, tapefb, tapec|
		var in = In.ar(dryBus, numChannels);
		var maxDelayTime = 8;
		var decayTime, delay, delayfb, loop;

		delayfb = tapefb.clip(0, 0.99);
		delay = (Lag.kr(taped, 0.1) + LPF.kr(PinkNoise.kr(0.015), 1)).clip(0.001, maxDelayTime); //wow
		loop = LocalIn.ar(numChannels);
		loop = DelayL.ar((loop*delayfb) + (in*tapeAmp), maxDelayTime, delay);
		loop = loop * WhiteNoise.ar(0.01,1); //flutter?
		loop = MantissaMask.ar(loop, 2);
		loop = CompanderD.ar(loop, 0.3, 1, (1-tapec).clip(0,1), 0.005, 0.005); //compression, but could be better
		loop = LPF.ar(tanh(loop)*1.2, 2700+SinOsc.kr(0.1,mul:20)-(1000*tapec)); //distortion and hi cutoff
		loop = HPF.ar(loop, 20);
		LocalOut.ar(LeakDC.ar(loop));
		loop = loop * EnvGen.kr(Env.asr, gate, doneAction:2);
		Out.ar(effectBus, loop);
	}, [\ir, \ir]).add;

	SynthDef("dirt_monitor" ++ numChannels, { |dryBus, effectBus, outBus, gate = 1|
		var drySignal = In.ar(dryBus, numChannels);
		var wetSignal = In.ar(effectBus, numChannels);
		//var signal = XFade2.ar(wetSignal, drySignal, dry * 2 - 1);
		var signal = wetSignal + drySignal;

		signal = Limiter.ar(signal);

		// or if you like it harsher
		//signal = tanh(signal);
		// or:
		//signal = distort(signal);

		signal = signal * EnvGen.kr(Env.asr, gate, doneAction:2);
		Out.ar(outBus, signal)
	}, [\ir, \ir, \kr, \kr]).add;

	// thanks to Jost Muxfeld and James McCartney
	// note that "size" is not room size, just a depth metaphor

	SynthDef("dirt_reverb" ++ numChannels, { |dryBus, effectBus, gate = 1, room = 0, size = 0.1, dry = 0|
		var in, snd, loop, depth;

		in = In.ar(dryBus, numChannels).asArray.sum;

		in = in * room.lag(LFNoise1.kr(1).range(0.01, 0.02)); // regulate input

		4.do { in = AllpassN.ar(in, 0.03, { Rand(0.005, 0.02) }.dup(numChannels), 1) };

		depth = size.lag(0.02).linexp(0, 1, 0.01, 0.98); // change depth between 0.1 and 0.98
		loop = LocalIn.ar(numChannels) * { depth + Rand(0, 0.05) }.dup(numChannels);
		loop = OnePole.ar(loop, 0.5);  // 0-1

		loop = AllpassN.ar(loop, 0.05, { Rand(0.01, 0.05) }.dup(numChannels), 2);

		loop = DelayN.ar(loop, 0.3, [0.19, 0.26] + { Rand(-0.003, 0.003) }.dup(2));
		loop = AllpassN.ar(loop, 0.05, { Rand(0.03, 0.15) }.dup(numChannels), 2);

		loop = loop + in;
		loop = LeakDC.ar(loop);

		LocalOut.ar(loop);

		snd = loop;
		snd = snd * (1 - dry).lag(LFNoise1.kr(1).range(0.01, 0.02));

		DirtPause.ar(snd, graceTime:4);

		snd = snd * EnvGen.kr(Env.asr, gate, doneAction:2);

		Out.ar(effectBus, snd);

	}, [\ir, \ir]).add;

	// wub - an "always-on" monophonic (per orbit) synth
	// to access this from Tidal, you'll need to define all the parameters, like this;
	//     let (wubn, _) = pF "wubn" (Just 0)
	// parameters are
	// wub - amplitude
	// wubn - note value (can be fractional)
	// wubf - frequency of amplitude modulation (Hz)
	// wubd - depth of amplitude modulation
	// wubw - duty cycle width for VarSaw
	// wubt - detune amount (in semitones)
	// wubp - portamento lag time (in seconds)
	// you can add your own params, you'll need to also put them in initDefaultGlobalEffects in SuperDirt.sc
	// and if you want the params to have non-zero values when left unspecified in Tidal, add that to playSynths in DirtEvent.sc
	// (the defaults in the SynthDef below only apply when the synth is first started, on SuperDirt bootup)
	SynthDef("dirt_wub" ++ numChannels, {|dryBus, effectBus, gate=1, wub=0.0,
		wubn=0, wubf=8, wubd=1, wubw=0.5, wubt=0.1, wubp=1.0, wubv=0|
		var signal, mod, famp, ffreq, fmodfreq, fdepth, fwidth, fdetune, env, farray, fvoice;
		// the envelope keeps things from playing infinitely after you hush Tidal
		// though you can always explicitly send a `wub "0"` message to stop it
		// side effect is that if you don't change parameters the wub eventually goes away
		// if you don't like this just remove the `env` from the final line
		env = EnvGen.ar(Env.perc(0.01, 20), gate:Changed.kr(wub+wubn+wubf+wubd+wubw+wubt));
		famp = Lag.kr(wub, 0.7);
		// next line is portamento, the lag time itself is a parameter
		ffreq = Lag.kr((wubn+60).midicps, wubp);
		fmodfreq= Lag.kr(wubf,1.0);
		fdepth = Lag.kr(wubd, 1.0);
		fwidth = Lag.kr(wubw,1.0);
		fdetune = Lag.kr(wubt,1.0);
		fvoice = Lag.kr(wubv,1.0);
		mod = SinOsc.ar(fmodfreq).range(1.0-fdepth, 1.0);
		farray = ffreq * (2**([-1,0,1]*fdetune/12));
		signal = SelectX.ar(fvoice, [
			Splay.ar(VarSaw.ar(farray, 0, fwidth)),
			Splay.ar(SinOscFB.ar(farray, fwidth)),
			Splay.ar(FBSineN.ar(22050, SinOsc.kr(fmodfreq*1.01).range(1,1+fdepth), SinOsc.kr(fmodfreq*0.99).range(0,fwidth), 1, farray/22050*2pi, 0, 0)),
			Splay.ar(Pulse.ar(farray, fwidth* (SinOsc.kr(fmodfreq).range(0.9,1.1))))
		]);
		Out.ar(effectBus, signal*env*mod*famp);
	}, [\ir,\ir,\kr,  \kr,\kr,\kr,\kr,\kr,\kr]).add;

	SynthDef("dirt_leslie" ++ numChannels, { |dryBus, effectBus, gate = 1, leslie=0, lrate=6.7, lsize=0.3|
		var in, distance, throb, sound1, sound2, bal1, bal2;
		in = In.ar(dryBus, numChannels);
		ReplaceOut.ar(dryBus, in*(1-leslie));
		distance = SinOsc.ar(Lag.kr(lrate,10), 0).range(0, lsize);
		throb = SinOsc.ar(Lag.kr(lrate*0.8, 20), 0).range(0,lsize*1.3);
		bal1 = SinOsc.kr(Lag.kr(lrate*0.8, 4), pi/2).range(-0.2,0.2);
		bal2 = SinOsc.kr(Lag.kr(lrate,2), pi/2).range(-0.4, 0.4);
		sound2 = HPF.ar(in, 800);
		sound1 = in - sound2;
		sound1 = leslie * (1.0 - throb) * sound1;
		sound1 = Balance2.ar(sound1[0], sound1[1], bal1);
		sound2 = DelayC.ar(sound2, 1, distance / 343);
		sound2 = leslie * (1.0 - distance) * sound2;
		sound2 = Balance2.ar(sound2[0], sound2[1], bal2);
		Out.ar(effectBus, 1.2*(sound1+sound2));
	}, [\ir, \ir]).add;


	"---- core synth defs loaded ----".postln;

}.value
);
