module ss13.atmos.reactions;

import ss13.atmos.gas, ss13.atmos.regions;

auto reactions = [
    &HandleFireReaction,
    // Add to this list as necessary.
];

void HandleReactions(ref GasMixture gas, const float volume) {
    foreach(reaction; reactions)
        reaction(gas, volume);
}


//enum float FireMinimumTemperatureToSpread = 150.degC; // K
//enum float FireMinimumPlasma              = VisiblePlasmaMoles; // Moles
//enum float FireMinimumPlasmaEx            = FireMinimumPlasma / 2; // Moles
//enum float FireIgniteThreshold            = 0.01;
//enum float FireExtinquishThreshold        = 0.0001;
enum float PlasmaMinimumBurnTemperature   = 100.degC; // K
enum float PlasmaUpperTemperature         = 1370.degC; // K
enum float OxygenBurnRateBase             = 1.4;
enum float PlasmaBurnRateDelta            = 8;
enum float PlasmaOxygenFullburn           = 10;
enum float FirePlasmaEnergyReleased       = 3000000;

//enum float MinimumHeatCapacity            = 0.0003;

void HandleFireReaction(ref GasMixture gas, const float volume) {
    immutable temp = gas.temperature;
    //immutable burning = gas.flags & GasFlags.Burning;

    gas.flags &= ~GasFlags.Burning;
    if (temp < PlasmaMinimumBurnTemperature) return;

    immutable originalHeatCapacity = gas.heatCapacity;
    if (originalHeatCapacity < float.epsilon) return;

    immutable plasma = gas.moles[gasIndex!"plasma"];
    immutable oxygen = gas.moles[gasIndex!"oxygen"];

    //if (!burning && plasma < FireMinimumPlasma) return;
    //if (burning && plasma < FireMinimumPlasmaEx) return;
    if (plasma < float.epsilon) return;

    immutable tempScale =
        (temp > PlasmaUpperTemperature)
        ? 1
        : (temp - PlasmaMinimumBurnTemperature) / (PlasmaUpperTemperature - PlasmaMinimumBurnTemperature);

    if (tempScale < float.epsilon) return;

    immutable oxygenBurnRate = OxygenBurnRateBase - tempScale;
    immutable plasmaBurnRate =
        (oxygen > plasma * PlasmaOxygenFullburn)
        ? tempScale * plasma / PlasmaBurnRateDelta
        : tempScale * oxygen / PlasmaOxygenFullburn / PlasmaBurnRateDelta;

    //if (burning) {
    //    if (plasmaBurnRate < FireExtinquishThreshold) return;
    //}
    //else {
    //    if (plasmaBurnRate < FireIgniteThreshold) return;
    //}
    if (plasmaBurnRate < 0.0003) return;

    gas.moles[gasIndex!"plasma"] -= plasmaBurnRate;
    gas.moles[gasIndex!"oxygen"] -= plasmaBurnRate * oxygenBurnRate;
    gas.moles[gasIndex!"carbon dioxide"] += plasmaBurnRate;
    gas.flags |= GasFlags.Burning;

    immutable energyReleased = plasmaBurnRate * FirePlasmaEnergyReleased;
    immutable newHeatCapacity = gas.heatCapacity;
    
    if (newHeatCapacity > 0)
        gas.temperature = (temp * originalHeatCapacity + energyReleased) / newHeatCapacity;
}
