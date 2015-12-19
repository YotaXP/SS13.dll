module ss13.atmos.gas;

import std.range, std.algorithm, std.conv;
import ss13.atmos.structures;

struct GasInfo {
    string name;
    string shortName;
    float specificHeat;
}

static immutable GasInfo[] gasTypes = [
    //      Full Name,        Short, Heat Capacity
    GasInfo("oxygen",         "O2",  20),
    GasInfo("nitrogen",       "N",   20),
    GasInfo("plasma",         "Pl", 300),
    GasInfo("nitrous oxide",  "N2O", 40),
    GasInfo("carbon dioxide", "CO2", 30),
];
enum size_t gasIndex(string gas) = gasTypes.countUntil!(g => g.name == gas);

enum float oneAtmosphere     = 101.325; // kPa
enum float idealGasEquation  = 8.31;    // kPa*L/(K*mol)
enum float temperatureCosmicMicrowaveBackround = 2.7; // K

float degC(float kelvin) pure nothrow {
    return kelvin + 273.15;
}
float bars(float b) pure nothrow {
    return b * oneAtmosphere;
}

enum float VisiblePlasmaMoles = 0.5;
enum float VisibleN2OMoles    = 1;

enum GasFlags : uint {
    None    = 0,
    Burning = 1,
}

pragma(msg, "GasMixture.sizeof: " ~ GasMixture.sizeof.to!string);
// 28 Bytes (with 5 gasses)
struct GasMixture {
    float[gasTypes.length] moles = 0;
    float temperature = temperatureCosmicMicrowaveBackround; // K
    GasFlags flags = GasFlags.None;

    // Calculates pressure in kPa.
    float pressure(float volume) const pure nothrow {
        //if (volume < float.epsilon) return 0;
        return moles[].sum * idealGasEquation * temperature / volume;
    }

    float heatCapacity() const pure nothrow {
        return reduce!((s, i) => s + moles[i] * gasTypes[i].specificHeat)(0f, iota(0, gasTypes.length));
    }

    // Adds gas from one GasMixture to this one.  THIS DOES NOT REMOVE THE GAS FROM THE SOURCE!
    void addGas(GasMixture source, float percentage = 1) pure nothrow {
        float otherHC = source.heatCapacity() * percentage;
        if (otherHC < float.epsilon) return;
        float thisHC = this.heatCapacity();
        moles[] += source.moles[] * percentage;
        temperature = (temperature * thisHC + source.temperature * otherHC) / (thisHC + otherHC);
    }

    void moveGasMoles(ref GasMixture source, float molesToMove) pure nothrow {
        scope(failure) return; // Hiding errors for now.  Examine this further later.

        immutable totalMolesSource = source.moles.reduce!"a+b";
        molesToMove = min(molesToMove, totalMolesSource);
        if (molesToMove <= float.epsilon) return;

        immutable totalMoles = moles.reduce!"a+b";
        immutable percentage = molesToMove / totalMoles;

        float otherHC = source.heatCapacity() * percentage;
        if (otherHC < float.epsilon) return;
        float thisHC = this.heatCapacity();
        moles[] += source.moles[] * percentage;
        temperature = (temperature * thisHC + source.temperature * otherHC) / (thisHC + otherHC);
        source.moles[] *= 1 / percentage;
    }
}

// Default gas levels for human-breathable air.
GasMixture airMix(float pressure, float temperature, float volume) {
    return buildGasMix(["O2": 0.21f, "N": 0.79f], pressure, temperature, volume);
}

GasMixture buildGasMix(float[string] gasLevels, float pressure, float temperature, float volume) pure nothrow {
    assert(pressure >= 0 && temperature > 0 && volume >= 0);
    GasMixture gas;
    foreach (string gasName; gasLevels.byKey) {
        immutable gasIndex = gasTypes.countUntil!(g => g.name == gasName || g.shortName == gasName);
        if (gasIndex == -1) continue;
        gas.moles[gasIndex] = gasLevels[gasName];
    }
    immutable ratioTotal = gas.moles[].sum;
    if (ratioTotal < float.epsilon)
        gas.moles[] = 0;
    else
        gas.moles[] *= 1 / ratioTotal * pressure * volume / (temperature * idealGasEquation);
    gas.temperature = temperature;
    return gas;
}


