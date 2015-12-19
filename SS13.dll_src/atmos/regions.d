module ss13.atmos.regions;

import std.typecons, std.parallelism, std.range, std.algorithm;
import ss13.atmos.gas, ss13.atmos.reactions;
import byond;

enum float tileVolume        = 2500; // L
enum float gasAccellRate     = 0.2;  // 0-1 percentage
enum float velocityDampening = 0.9;  // 0-1 multiplier
enum float dispersalFactor   = 0.1;  // 0-1 percentage for each direction

enum TileStates : byte {
    None = 0,

    BlockedNorth = 0b00_0001,
    BlockedSouth = 0b00_0010,
    BlockedEast  = 0b00_0100,
    BlockedWest  = 0b00_1000,
    BlockedAll   = 0b00_1111,

    Static       = 0b01_0000,
}

// Tracks what visual overlays should be shown on a tile.
enum HazardStates : byte {
    None   = 0b000,
    Fire   = 0b001,
    Plasma = 0b010,
    N2O    = 0b100,
}

struct Region {
    GasMixture[] gasses;
    TileStates[] states;
    HazardStates[] hazards;
    float[2][] velocities; // tiles per iteration * moles
    immutable size_t width, height;

    this(size_t width, size_t height) {
        this.width = width; this.height = height;
        gasses = new GasMixture[width * height];
        states = new TileStates[width * height];
        states[] = TileStates.None;
        hazards = new HazardStates[width * height];
        hazards[] = HazardStates.None;
        velocities = new float[2][width * height];
        velocities[] = [0f, 0f];
    }

    ref auto gas(size_t x, size_t y)      { return gasses[x + y * width]; }
    ref auto state(size_t x, size_t y)    { return states[x + y * width]; }
    ref auto hazard(size_t x, size_t y)   { return hazards[x + y * width]; }
    ref auto velocity(size_t x, size_t y) { return velocities[x + y * width]; }
}

final class AutomataRegion {
    Region* currentRegion;
    Region* workingRegion;
    size_t width, height;
    Tuple!(size_t,size_t)[] bands1;
    Tuple!(size_t,size_t)[] bands2;
    bool runningCycle = false;
    HazardStates[size_t[2]] updatedHazards;

    size_t iterations = 0;

    this(size_t width, size_t height, size_t maxThreads = 0) {
        this.width = width; this.height = height;
        currentRegion = new Region(width, height);
        workingRegion = new Region(width, height);

        if (maxThreads <= 0) maxThreads = defaultPoolThreads();
        auto threads = min(maxThreads, height / 4);
        if (threads > 1) {
            auto bandSize = height / (threads * 2);
            auto points = iota(0, threads * 2).map!(n => n * bandSize).chain(only(height));
            auto bands = zip(points, points.dropOne);
            foreach (pair; bands) {
                bands1 ~= pair;
                LogDebug("Band: %d..%d", pair[0], pair[1]);
                swap(bands1, bands2);
            }
        }
        else if (height > 0)
            bands1 ~= tuple(0u, height);
    }

    void RunCycle() {
        assert(!runningCycle);
        runningCycle = true;

        // Zero out workingRegion's gas.
        foreach (pair; bands1.chain(bands2).parallel(1))
            workingRegion.gasses[pair[0] * width .. pair[1] * width].fill(GasMixture());

        // And copy over currentRegion's states. TODO: Lock for this!
        foreach (pair; bands1.chain(bands2).parallel(1)) {
            immutable start = pair[0] * width;
            immutable end   = pair[1] * width;
            workingRegion.states[start..end] = currentRegion.states[start..end];
            workingRegion.velocities[start..end] = currentRegion.velocities[start..end];
        }

        // Build velocity.
        foreach (pair; bands1.chain(bands2).parallel(1))
            BuildVelocity(pair[0], pair[1]);

        // Call IterateRegion to process strips of the map.
        foreach (pair; bands1.parallel(1))
            IterateRegion(pair[0], pair[1]);

        // Two sets of strips designed to prevent the possibility of race conditions.
        foreach (pair; bands2.parallel(1))
            IterateRegion(pair[0], pair[1]);

        // Run all gas reactions.
        foreach (pair; bands1.chain(bands2).parallel(1))
            foreach (y; iota(pair[0], pair[1])) foreach (x; iota(0, width))
                if (!(currentRegion.state(x, y) & TileStates.Static))
                    HandleReactions(workingRegion.gas(x, y), tileVolume);

        // Update hazard states. (Associative arrays are not thread-safe, so we must do this synchronously. :'C )
        foreach (y; iota(0, height)) foreach (x; iota(0, width))
            UpdateTileHazard(x, y);
                

        swap(currentRegion, workingRegion);
        ++iterations;

        runningCycle = false;
    }

    void UpdateTileHazard(size_t x, size_t y) {
        const gas = &workingRegion.gas(x, y);
        auto oldHazard = &workingRegion.hazard(x, y);
        HazardStates newHazard = HazardStates.None;
        if (gas.moles[gasIndex!"plasma"] > VisiblePlasmaMoles)        newHazard |= HazardStates.Plasma;
        if (gas.moles[gasIndex!"nitrous oxide"] > VisiblePlasmaMoles) newHazard |= HazardStates.N2O;
        if (gas.flags & GasFlags.Burning)                             newHazard |= HazardStates.Fire;
        if (*oldHazard != newHazard) {
            updatedHazards[[x, y]] = newHazard;
            *oldHazard = newHazard;
        }
    }

    private void BuildVelocity(size_t startY, size_t endY)
    in {
        assert(endY > startY + 1);
    }
    body {
        auto crs = currentRegion.states;
        auto crg = currentRegion.gasses;
        auto crm = currentRegion.velocities;
        auto wrm = workingRegion.velocities;

        immutable width_m1 = width - 1; // -1 here to avoid extra adds.
        immutable height_m1 = height - 1;

        foreach (size_t y; startY..endY) foreach(size_t x; 0..width) {
            immutable i = x + y * width;
            immutable iEast  = i + 1;
            immutable iNorth = i + width;

            TileStates blocked = crs[i];
            if (x >= width_m1  || crs[iEast ] & TileStates.BlockedWest ) blocked |= TileStates.BlockedEast;
            if (y >= height_m1 || crs[iNorth] & TileStates.BlockedSouth) blocked |= TileStates.BlockedNorth;

            if (crs[i] & TileStates.Static) {
                if (!(blocked & TileStates.BlockedEast)  && (crs[iEast]  & TileStates.Static)) blocked |= TileStates.BlockedEast;
                if (!(blocked & TileStates.BlockedNorth) && (crs[iNorth] & TileStates.Static)) blocked |= TileStates.BlockedNorth;
            }

            immutable thisP = crg[i].pressure(tileVolume);
            auto velocity   = crm[i];

            if (blocked & TileStates.BlockedEast)
                velocity[0] = 0;
            else {
                immutable eastP  = crg[iEast].pressure(tileVolume);
                if (thisP + eastP < float.epsilon)
                    velocity[0] = 0;
                else {
                    immutable eastPD = (thisP - eastP) / (thisP + eastP);
                    velocity[0] = velocity[0] * velocityDampening + eastPD * gasAccellRate;
                }
            }

            if (blocked & TileStates.BlockedNorth)
                velocity[1] = 0;
            else {
                immutable northP  = crg[iNorth].pressure(tileVolume);
                if (thisP + northP < float.epsilon)
                    velocity[1] = 0;
                else {
                    immutable northPD = (thisP - northP) / (thisP + northP);
                    velocity[1] = velocity[1] * velocityDampening + northPD * gasAccellRate;
                }
            }

            //velocity[0] = clamp(velocity[0], -0.5, 0.5);
            //velocity[1] = clamp(velocity[1], -0.5, 0.5);
            wrm[i] = velocity;
        }
    }

    private void IterateRegion(size_t startY, size_t endY)
    in {
        assert(endY > startY + 1);
    }
    body {
        auto crs = currentRegion.states;
        auto crg = currentRegion.gasses;
        auto wrg = workingRegion.gasses;
        auto wrm = workingRegion.velocities;

        immutable width_m1 = width - 1; // -1 here to avoid extra adds.
        immutable height_m1 = height - 1;

        foreach(size_t y; startY..endY) foreach(size_t x; 0..width) {
            immutable i = x + y * width;
            immutable iEast  = i + 1;
            immutable iNorth = i + width;
            immutable iWest  = i - 1;
            immutable iSouth = i - width;

            TileStates blocked = crs[i];
            if (x >= width_m1  || crs[iEast ] & TileStates.BlockedWest ) blocked |= TileStates.BlockedEast;
            if (y >= height_m1 || crs[iNorth] & TileStates.BlockedSouth) blocked |= TileStates.BlockedNorth;
            if (x <= 0         || crs[iWest ] & TileStates.BlockedEast ) blocked |= TileStates.BlockedWest;
            if (y <= 0         || crs[iSouth] & TileStates.BlockedNorth) blocked |= TileStates.BlockedSouth;

            auto mEast  = wrm[i][0] + dispersalFactor;
            auto mNorth = wrm[i][1] + dispersalFactor;
            auto mWest  = (blocked & TileStates.BlockedWest)  ? dispersalFactor : -wrm[iWest ][0] + dispersalFactor;
            auto mSouth = (blocked & TileStates.BlockedSouth) ? dispersalFactor : -wrm[iSouth][1] + dispersalFactor;
            immutable mRatio = max(1, 1 / (1 + mEast + mNorth + mWest + mSouth));
            mEast  *= mRatio;
            mNorth *= mRatio; // Normalize 'em, so they don't suck out more air than the tile has to give.
            mWest  *= mRatio;
            mSouth *= mRatio;

            float percentageRemoved = 0;
            if (!(blocked & TileStates.BlockedEast) && mEast > 0) {
                if (!(crs[iEast] & TileStates.Static))
                    wrg[iEast].addGas(crg[i], mEast);
                percentageRemoved += mEast;
            }
            if (!(blocked & TileStates.BlockedNorth) && mNorth > 0) {
                if (!(crs[iNorth] & TileStates.Static))
                    wrg[iNorth].addGas(crg[i], mNorth);
                percentageRemoved += mNorth;
            }
            if (!(blocked & TileStates.BlockedWest) && mWest > 0) {
                if (!(crs[iWest] & TileStates.Static))
                    wrg[iWest].addGas(crg[i], mWest);
                percentageRemoved += mWest;
            }
            if (!(blocked & TileStates.BlockedSouth) && mSouth > 0) {
                if (!(crs[iSouth] & TileStates.Static))
                    wrg[iSouth].addGas(crg[i], mSouth);
                percentageRemoved += mSouth;
            }

            if (crs[i] & TileStates.Static)
                wrg[i] = crg[i];
            else
                wrg[i].addGas(crg[i], 1 - percentageRemoved);
        }
    }

    //private void OldIterateRegion(size_t startY, size_t endY)
    //in {
    //    assert(endY > startY + 2);
    //}
    //body {
    //    auto crs = currentRegion.states;
    //    auto crg = currentRegion.gasses;
    //    auto wrg = workingRegion.gasses;
    //
    //    size_t x = 0;
    //    size_t y = startY;
    //    immutable width_m1 = width - 1; // -1 here to avoid extra adds.
    //    immutable height_m1 = height - 1;
    //
    //    foreach(size_t i; startY * width .. endY * width) {
    //        // If static, skip this tile.
    //        if (!(crs[i] & TileStates.Static)) {
    //            immutable iNorth = i + width;
    //            immutable iSouth = i - width;
    //            immutable iEast  = i + 1;
    //            immutable iWest  = i - 1;
    //
    //            TileStates blocked = crs[i];
    //            if (y >= height_m1 || crs[iNorth] & TileStates.BlockedSouth) blocked |= TileStates.BlockedNorth;
    //            if (y <= 0         || crs[iSouth] & TileStates.BlockedNorth) blocked |= TileStates.BlockedSouth;
    //            if (x >= width_m1  || crs[iEast ] & TileStates.BlockedWest ) blocked |= TileStates.BlockedEast;
    //            if (x <= 0         || crs[iWest ] & TileStates.BlockedEast ) blocked |= TileStates.BlockedWest;
    //
    //            size_t openCount = 5;
    //            //if (blocked & TileStates.BlockedNorth) --openCount;
    //            //if (blocked & TileStates.BlockedSouth) --openCount;
    //            //if (blocked & TileStates.BlockedEast)  --openCount;
    //            //if (blocked & TileStates.BlockedWest)  --openCount;
    //
    //            const gas = crg[i];
    //            immutable float thisP = gas.pressure();
    //            float northPD = 0, southPD = 0, eastPD = 0, westPD = 0;
    //            if (!(blocked & TileStates.BlockedNorth)) northPD = max(0, 1 - crg[iNorth].pressure() / thisP);
    //            if (!(blocked & TileStates.BlockedSouth)) southPD = max(0, 1 - crg[iSouth].pressure() / thisP);
    //            if (!(blocked & TileStates.BlockedEast )) eastPD  = max(0, 1 - crg[iEast ].pressure() / thisP);
    //            if (!(blocked & TileStates.BlockedWest )) westPD  = max(0, 1 - crg[iWest ].pressure() / thisP);
    //
    //            if (northPD > float.epsilon && !(blocked & TileStates.BlockedNorth) && !(crs[iNorth] & TileStates.Static))
    //                wrg[iNorth].addGas(gas, northPD / openCount);
    //            if (southPD > float.epsilon && !(blocked & TileStates.BlockedSouth) && !(crs[iSouth] & TileStates.Static))
    //                wrg[iSouth].addGas(gas, southPD / openCount);
    //            if (eastPD  > float.epsilon && !(blocked & TileStates.BlockedEast ) && !(crs[iEast ] & TileStates.Static))
    //                wrg[iEast ].addGas(gas, eastPD  / openCount);
    //            if (westPD  > float.epsilon && !(blocked & TileStates.BlockedWest ) && !(crs[iWest ] & TileStates.Static))
    //                wrg[iWest ].addGas(gas, westPD  / openCount);
    //
    //            wrg[i].addGas(gas, 1 - (northPD + southPD + eastPD + westPD) / openCount);
    //        }
    //        else
    //            wrg[i] = crg[i];
    //
    //        if (++x >= width) {
    //            x = 0;
    //            ++y;
    //        }
    //    }
    //}
}
