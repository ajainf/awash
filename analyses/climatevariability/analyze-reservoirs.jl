#cd("../../src")
include("../../src/nui.jl")
config = readconfig("../configs/standard-10year.yml");
config["timestep"] = 12

# Optimization without reservoirs
config["rescap"] = "zero";
include("../../src/optimize-surface.jl");
writecsv("../analyses/climatevariability/analyzereservoir/failuresin.csv", reshape(sol.sol[1:varlens[1]], numregions, numsteps));

# Optimization with reservoirs at their current capacities
config["rescap"] = "full";

#cache_clear()
include("../../src/optimize-surface.jl");
writecsv("../analyses/climatevariability/analyzereservoir/failurecon.csv", reshape(sol.sol[1:varlens[1]], numregions, numsteps));

include("../../src/simulate.jl")

savedata("../analyses/climatevariability/analyzereservoir/captures.csv", :Reservoir, :captures)

savedata("../analyses/climatevariability/analyzereservoir/storagecapmax.csv", :Reservoir, :storagecapacitymax)

savedata("../analyses/climatevariability/analyzereservoir/storage.csv", :Reservoir, :storage)


