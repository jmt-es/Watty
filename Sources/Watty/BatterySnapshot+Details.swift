import WattyCore

extension BatterySnapshot {
    func fillingMissingDetails(from previous: BatterySnapshot) -> BatterySnapshot {
        var merged = self
        merged.cycleCount = cycleCount ?? previous.cycleCount
        merged.condition = condition ?? previous.condition
        merged.maximumCapacityPercent = maximumCapacityPercent ?? previous.maximumCapacityPercent
        merged.adapterRatedWatts = adapterRatedWatts ?? previous.adapterRatedWatts
        merged.adapterDescription = adapterDescription ?? previous.adapterDescription
        merged.powerMode = powerMode ?? previous.powerMode
        return merged
    }
}
