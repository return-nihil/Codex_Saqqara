// November 2025
// *************************************************************************


ServerOptions.devices;
Server.default.options.outDevice_("Soundflower (2ch)");

s.scope.window.alwaysOnTop_(true);
s.freqscope;
s.meter;
v = Volume.new(s);
v.gui;



(
// Server init
Server.default.options.inDevice_("M4");
Server.default.options.outDevice_("M4");
s.options.numBuffers = 1024 * 256;
s.options.memSize = 8192 * 128;
s.options.maxNodes = 1024 * 32;
//s.options.numInputBusChannels = 2;
s.options.numOutputBusChannels = 4;
o = NetAddr.new("127.0.0.1", 57121);
s.latency = 0.25;


// Midi
MIDIClient.init;
MIDIIn.connectAll;


// GLOBALS
~notestart_midi_pedalboard = 21;
~n_orbits = 12;
~osc_viz = NetAddr("127.0.0.1", 57121);
~thresh = 0.7;


// **************************************************************************
// AUXILIARY

// CLEANUP
~cleanup = {
    s.newBusAllocators;
    ServerBoot.removeAll;
    ServerTree.removeAll;
    ServerQuit.removeAll;
    s.freeAll;
};
ServerQuit.add(~cleanup);

// **************************************************************************
// BUFFERS
~buffers_init = {
    // recording buffers
    ~bufferZ = [1, 2, 3, 4, 5].collect { Buffer.alloc(s, s.sampleRate * 1, 1) };
    // wavetable buffers
    ~buffers_wt = [1, 2, 3, 4, 5].collect { Buffer.alloc(s, 2048) };
	~buffers_nmf = [1, 2, 3, 4, 5].collect { Buffer.alloc(s, s.sampleRate * 1, 1) };
	~bufferProcessing = Array.fill(~bufferZ.size, false);
};

// **************************************************************************

// **************************************************************************
// ZERO CROSSINGS + WAVETABLE CREATION --> import!

~find_zeroC = { |buf|
    var thresh_idx;
    buf.loadToFloatArray(action: { |array|
        var normalized = array / array.max.abs;
        ~zeroC = [];
        thresh_idx = normalized.detectIndex { |sample| sample.abs >= ~thresh };
        (thresh_idx..(normalized.size - 2)).do { |i|
            var curr = normalized[i];
            var next = normalized[i + 1];
            if (((curr >= 0 and: { next < 0 }) or: (curr <= 0 and: { next > 0 })) and: { ~zeroC.size < 10 }) {
                ~zeroC = ~zeroC.add(i + 1);
            };
        };
    });
};


~create_wt = { |num_zcs, source_buf, target_buf, bufn = 0|
    var seg, interp, interpArray, interpArray2;
    source_buf.loadToFloatArray(action: { |array|
        seg = array.copyRange(~zeroC[0], ~zeroC[num_zcs - 1]);
        interp = Signal.newFrom(seg).resamp1(2048);

        target_buf.loadCollection(interp);
		target_buf.normalize(newmax:1);

        interpArray = interp.as(Array).normalize(min: -1.0, max: 1.0);

        ~osc_viz.sendMsg("/wavetable", bufn, *interpArray);
        "sent wavetable for buf %".format(bufn).postln;
    });
    //^target_buf;
};


~process_NMF = { | source_buf, target_buf, n_components = 3 |
	FluidBufNMF.processBlocking(s,
		source_buf,
		resynth:target_buf,
		resynthMode:1,
		components:n_components,
		action:{"saved non-negative matrix".postln;})
};



// **************************************************************************
// SERVER BOOT
s.waitForBoot {
    ~buffers_init.();
    ~dirt = SuperDirt(2, s);
    ~dirt.start(57120, 0 ! 12);
	// removed leslie and delay from /Users/ardan/Library/Application\ Support/SuperCollider/downloaded-quarks/SuperDirt/classes/DirtOrbit.sc !!!
    s.sync;

    "CS_synthdefs_v2-1.scd".loadRelative;
    StageLimiter.activate;
    s.sync;

    "ENVIRONMENT READY".postln;
};



// **************************************************************************
// MIDI HANDLER
MIDIIn.program = { |src, chan, midinote|
    var bufferz = (midinote - ~notestart_midi_pedalboard);

    if(bufferz.isNil.not and: { bufferz >= 0 and: { bufferz < ~bufferZ.size } }) {

        if(~bufferProcessing[bufferz].not) {
            ~bufferProcessing[bufferz] = true;

            Synth(\rec, [\bufnum, ~bufferZ[bufferz].bufnum, \gate, 1]);

            Routine({
                1.05.wait;
                ~process_NMF.(~bufferZ[bufferz], ~buffers_nmf[bufferz]);
                ~find_zeroC.(~bufferZ[bufferz]);
                ~create_wt.(3, ~bufferZ[bufferz], ~buffers_wt[bufferz], bufferz);

                ~bufferProcessing[bufferz] = false;
            }).play;

            ("Recording on buffer " + bufferz).postln;
        } {
            ("Buffer " + bufferz + " is already being processed.").postln;
        };
    } {
        "Invalid MIDI note: %".format(midinote).postln;
    };
};

); // <--- here!!
