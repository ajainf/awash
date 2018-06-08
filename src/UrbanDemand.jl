## Urban Water Demand Component
#
# Comprises domestic, commerical and public supplied industrial
# sectors.

using Mimi
using DataFrames
include("lib/readconfig.jl")

@defcomp UrbanDemand begin
    regions = Index()
    scenarios = Index()

    # Urban demands - exogeneous for now
    domesticdemand = Parameter(index=[regions, scenarios, time], unit="1000 m^3")

    # Demanded water
    waterdemand = Variable(index=[regions, scenarios, time],unit="1000 m^3")
end

"""
The quantity of water demanded at each timestep
"""
function run_timestep(c::UrbanDemand, tt::Int)
    v = c.Variables
    p = c.Parameters
    d = c.Dimensions

    for rr in d.regions
        v.waterdemand[rr, :, tt] = p.domesticdemand[rr, :, tt]; # XXX: Where is commercial
    end
end

"""
Add an urban component to the model.
"""
function initurbandemand(m::Model)
    urbandemand = addcomponent(m, UrbanDemand);

    # data from USGS 2010 for the 2000 county definition
    recorded = getfilteredtable("extraction/USGS-2010.csv")

    urbandemand[:domesticdemand] = repeat(convert(Vector, recorded[:, :PS_To]) * 1383./12. * config["timestep"], outer=[1, numscenarios, numsteps])

    urbandemand
end

function constraintoffset_urbandemand_waterdemand(m::Model)
    gen(rr, tt) = m.external_parameters[:domesticdemand].values[rr,tt]
    hallsingle(m, :UrbanDemand, :waterdemand, gen, [:scenarios])
end
