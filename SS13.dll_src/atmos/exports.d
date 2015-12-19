module ss13.atmos.exports;

import std.conv, std.range, std.algorithm, std.datetime, std.random, std.format, std.json, core.thread, core.sync.rwmutex;
import ss13.atmos.gas, ss13.atmos.regions;
import byond;

__gshared AutomataRegion AtmosRegion;
//AtmosWorkerThread workerThread;
__gshared ReadWriteMutex atmosMutex;

class AtmosWorkerThread : Thread
{
    this(void delegate() f) {
        name = "Atmos worker thread.";
        isDaemon = true;
        super(f);
    }
}

mixin ByondFunction!("Atmos_Initialize", (size_t width, size_t height, size_t maxThreads) {
    if (atmosMutex)
        throw new Exception("Atmos has already been initialized.");
    
    atmosMutex = new ReadWriteMutex();
    auto atmosLock = atmosMutex.writer;
    atmosLock.lock;
    new AtmosWorkerThread({
        StopWatch sw;
        sw.start();

        AtmosRegion = new AutomataRegion(width, height, maxThreads);
        //AtmosRegion.currentRegion.gasses[] = airMix!(1.bars, 20.degC, tileVolume);

        foreach(ref gas; AtmosRegion.currentRegion.gasses) {
            switch(dice(3, 5, 0.1)) {
                case 0:
                    gas = GasMixture();
                    break;
                case 1:
                    gas = airMix(1.bars, 20.degC, tileVolume);
                    break;
                case 2:
                    gas = buildGasMix(["Pl": 1], 5.bars, 20.degC, tileVolume);
                    break;
                default: assert(0);
            }
        }

        //foreach(x; iota(0, 15)) foreach(y; iota(0, 15))
        //    if(x + y < 12 || x + y > 16)
        //        AtmosRegion.currentRegion.gas(x, y) = airMix(1.bars, 20.degC, tileVolume);

        sw.stop();
        atmosLock.unlock;
    
        LogDebug("Atmos initialized.  %dx%d  Max threads: %d  Avg pressure: %f  Init time: %dms", width, height, maxThreads,
                 AtmosRegion.currentRegion.gasses.map!(g => g.pressure(tileVolume)).sum / AtmosRegion.currentRegion.gasses.length, sw.peek.msecs);
    }).start;
});

mixin ByondFunction!("Atmos_GetInfo", () {
    if (!atmosMutex)
        throw new Exception("Atmos has not been initialized.");

    string[string] list;
    synchronized(atmosMutex.reader)
        list["iterations"] = AtmosRegion.iterations.to!string;
    return list2params(list);
});

mixin ByondFunction!("Atmos_RunCycle", (size_t iterations) {
    if (!atmosMutex)
        throw new Exception("Atmos has not been initialized.");
    
    auto atmosLock = atmosMutex.writer;
    atmosLock.lock;
    new AtmosWorkerThread({
        StopWatch sw;
        sw.start();

        foreach(i; 0..iterations)
            AtmosRegion.RunCycle();

        sw.stop();
        LogDebug("Iterations: %d  Time: %dms.  Avg pressure: %f  Avg temp: %f  Avg velocity: %f", iterations, sw.peek.msecs,
                 AtmosRegion.currentRegion.gasses.map!(g => g.pressure(tileVolume)).sum / AtmosRegion.currentRegion.gasses.length,
                 AtmosRegion.currentRegion.gasses.map!(g => g.temperature).sum / AtmosRegion.currentRegion.gasses.length,
                 AtmosRegion.currentRegion.velocities.map!"abs(a[0])+abs(a[1])".sum / (AtmosRegion.currentRegion.velocities.length * 2));
        atmosLock.unlock;
    }).start;

});

mixin ByondFunction!("Atmos_GetHazardUpdates", () {
    if (!atmosMutex)
        throw new Exception("Atmos has not been initialized.");

    string[string] list;
    synchronized(atmosMutex.reader) {
        foreach(pair; AtmosRegion.updatedHazards.byKeyValue) {
            string hazards;
            if (pair.value & HazardStates.Plasma) hazards ~= "p";
            if (pair.value & HazardStates.N2O)    hazards ~= "n";
            if (pair.value & HazardStates.Fire)   hazards ~= "f";
            list[format("%d,%d", pair.key[0] + 1, pair.key[1] + 1)] = hazards;
        }
        AtmosRegion.updatedHazards = null;
    }

    //LogDebug("Pushed %d hazard update(s).", list.length);
    return list2params(list);
});

mixin ByondFunction!("Atmos_GetGasses", (size_t x, size_t y) {
    if (!atmosMutex)
        throw new Exception("Atmos has not been initialized.");

    string[string] list;
    synchronized(atmosMutex.reader) {
        auto ar = AtmosRegion;
        auto cr = ar.currentRegion;
        const gass = &cr.gas(x-1, y-1);
    
        const GasMixture* gas = &AtmosRegion.currentRegion.gas(x - 1, y - 1);
        list["temperature"] = gas.temperature.to!string;
        list["pressure"] = gas.pressure(tileVolume).to!string;
        list["moles"] = gas.moles[].sum.to!string;
        const velocity = AtmosRegion.currentRegion.velocity(x - 1, y - 1);
        list["velX"] = velocity[0].to!string;
        list["velY"] = velocity[1].to!string;
        foreach(i; iota(0, gasTypes.length)) {
            if (gas.moles[i] > float.epsilon)
                list[gasTypes[i].shortName] = gas.moles[i].to!string;
        }
    }

    return list2params(list);

    //JSONValue json;
    //synchronized(atmosMutex.reader) {
    //    auto ar = AtmosRegion;
    //    auto cr = ar.currentRegion;
    //    const gass = &cr.gas(x-1, y-1);
    //
    //    const GasMixture* gas = &AtmosRegion.currentRegion.gas(x - 1, y - 1);
    //    json["temperature"] = gas.temperature;
    //    json["pressure"] = gas.pressure(tileVolume);
    //    json["velocity"] = AtmosRegion.currentRegion.velocity(x - 1, y - 1);
    //    float[string] moles;
    //    float totalMoles = 0;
    //    foreach(i; iota(0, gasTypes.length)) {
    //        if (gas.moles[i] > float.epsilon)
    //            totalMoles += moles[gasTypes[i].shortName] = gas.moles[i];
    //    }
    //    json["moles"] = moles;
    //    json["totalMoles"] = totalMoles;
    //}
    //
    //return json;
});

mixin ByondFunction!("Atmos_SetTileGasses", (size_t x, size_t y, string paramsGasses) {
    if (!atmosMutex)
        throw new Exception("Atmos has not been initialized.");
    
    synchronized(atmosMutex.writer) {
        auto aaGasses = params2list(paramsGasses).to!(float[string]);
        if("temperature" in aaGasses) {
            AtmosRegion.currentRegion.gas(x - 1, y - 1)
                = buildGasMix(aaGasses, aaGasses.get("pressure", 1).bars, aaGasses.get("temperature", 20).degC, tileVolume);
            AtmosRegion.currentRegion.velocity(x - 1, y - 1)
                = [aaGasses.get("velX", 0), aaGasses.get("velY", 0)];
        }
        
        float blockE  = aaGasses.get("blockE", 0);
        float blockN  = aaGasses.get("blockN", 0);
        float blockW  = aaGasses.get("blockW", 0);
        float blockS  = aaGasses.get("blockS", 0);
        float fStatic = aaGasses.get("static", 0);
        if (blockE > 0)      AtmosRegion.currentRegion.state(x - 1, y - 1) |=  TileStates.BlockedEast;
        else if(blockE < 0)  AtmosRegion.currentRegion.state(x - 1, y - 1) &= ~TileStates.BlockedEast;
        if (blockN > 0)      AtmosRegion.currentRegion.state(x - 1, y - 1) |=  TileStates.BlockedNorth;
        else if(blockN < 0)  AtmosRegion.currentRegion.state(x - 1, y - 1) &= ~TileStates.BlockedNorth;
        if (blockW > 0)      AtmosRegion.currentRegion.state(x - 1, y - 1) |=  TileStates.BlockedWest;
        else if(blockW < 0)  AtmosRegion.currentRegion.state(x - 1, y - 1) &= ~TileStates.BlockedWest;
        if (blockS > 0)      AtmosRegion.currentRegion.state(x - 1, y - 1) |=  TileStates.BlockedSouth;
        else if(blockS < 0)  AtmosRegion.currentRegion.state(x - 1, y - 1) &= ~TileStates.BlockedSouth;
        if (fStatic > 0)     AtmosRegion.currentRegion.state(x - 1, y - 1) |=  TileStates.Static;
        else if(fStatic < 0) AtmosRegion.currentRegion.state(x - 1, y - 1) &= ~TileStates.Static;

        AtmosRegion.UpdateTileHazard(x - 1, y - 1);
    }
});

mixin ByondFunction!("Atmos_SetAllTileGasses", (string paramsGasses) {
    if (!atmosMutex)
        throw new Exception("Atmos has not been initialized.");

    synchronized(atmosMutex.writer) {
        auto aaGasses = params2list(paramsGasses).to!(float[string]);
        if("temperature" in aaGasses) {
            AtmosRegion.currentRegion.gasses[]
                = buildGasMix(aaGasses, aaGasses["pressure"].bars, aaGasses["temperature"].degC, tileVolume);
            AtmosRegion.currentRegion.velocities[]
                = [aaGasses.get("velX", 0), aaGasses.get("velY", 0)];
        }

        float blockE  = aaGasses.get("blockE", 0);
        float blockN  = aaGasses.get("blockN", 0);
        float blockW  = aaGasses.get("blockW", 0);
        float blockS  = aaGasses.get("blockS", 0);
        float fStatic = aaGasses.get("static", 0);
        if (blockE > 0)      AtmosRegion.currentRegion.states[] |=  TileStates.BlockedEast;
        else if(blockE < 0)  AtmosRegion.currentRegion.states[] &= ~TileStates.BlockedEast;
        if (blockN > 0)      AtmosRegion.currentRegion.states[] |=  TileStates.BlockedNorth;
        else if(blockN < 0)  AtmosRegion.currentRegion.states[] &= ~TileStates.BlockedNorth;
        if (blockW > 0)      AtmosRegion.currentRegion.states[] |=  TileStates.BlockedWest;
        else if(blockW < 0)  AtmosRegion.currentRegion.states[] &= ~TileStates.BlockedWest;
        if (blockS > 0)      AtmosRegion.currentRegion.states[] |=  TileStates.BlockedSouth;
        else if(blockS < 0)  AtmosRegion.currentRegion.states[] &= ~TileStates.BlockedSouth;
        if (fStatic > 0)     AtmosRegion.currentRegion.states[] |=  TileStates.Static;
        else if(fStatic < 0) AtmosRegion.currentRegion.states[] &= ~TileStates.Static;

        foreach(y; iota(0, AtmosRegion.height))
            foreach(x; iota(0, AtmosRegion.width))
                AtmosRegion.UpdateTileHazard(x, y);
    }
});