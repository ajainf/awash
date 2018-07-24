#cd("../../src")
include("../../src/nui.jl")
config = readconfig("../configs/standard-10year.yml");
savingresultspath = "../analyses/papers/paper2-yearly25/"
config["endmonth"] = "9/2030"
config["waterrightconst"] = nothing;
flowprop = [0. 0.37 0.5];
config["proportionnaturalflowforenvironment"] = flowprop[2];
surfconj = "conj";
savedem = false;
evalsim = false;
starty = 30;
endy = 30;

if isfile("../data/counties/extraction/withdrawals.jld")
    rm("../data/counties/extraction/withdrawals.jld")
    if isfile("../data/counties/extraction/waterfromgw.jld")
        rm("../data/counties/extraction/waterfromgw.jld")
    end
end
if isfile("../data/cache/counties/partialhouse.jld")
    rm("../data/cache/counties/partialhouse.jld")
    rm("../data/cache/counties/partialhouse2.jld")
end


#####################################
# CONJUNCTIVE USE w/ canals, no reservoirs
config["rescap"] = "zero"; # Optimization without reservoirs
config["filtercanals"] = nothing;
### CASE O: current situation
surfconj = "surface";
include("runoptisim.jl")

### CASE I: w/ SWGW constraint
surfconj = "conj";
config["waterrightconst"] = "SWGW"
include("runoptisim.jl")

### CASE II:w/ GW constraint
#config["waterrightconst"] = "GW"
#include("runoptisim.jl")

### CASE III: w/ SW constraint
#config["waterrightconst"] = "SW"
#include("runoptisim.jl")

### CASE IV: w/o constraint
config["waterrightconst"] = nothing
include("runoptisim.jl")



### CASE: Neighbors coord
include("../optradii/holdneighbors.jl")
# SAVE
confignamenew = "$configname-neighbors"
writecsv("$savingresultspath/gw-$confignamenew-$starty.csv", reshape(getparametersolution(house, sol_neighbors.sol, :waterfromgw),numcounties, numsteps))

writecsv("$savingresultspath/failure-$confignamenew-$starty.csv", reshape(getparametersolution(house, sol_neighbors.sol, :waterfromsupersource)+getparametersolution(house, sol_neighbors.sol, :quarterwaterfromsupersource),numcounties, numsteps))


include("../optradii/holdstate.jl")
confignamenew = "$configname-state"
writecsv("$savingresultspath/gw-$confignamenew-$starty.csv", reshape(getparametersolution(house, sol_after.sol, :waterfromgw),numcounties, numsteps))
writecsv("$savingresultspath/failure-$confignamenew-$starty.csv", reshape(getparametersolution(house, sol_after.sol, :waterfromsupersource)+getparametersolution(house, sol_after.sol, :quarterwaterfromsupersource),numcounties, numsteps))

