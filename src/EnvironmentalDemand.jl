## Environmental Water Demand Component

using Mimi
using DataFrames

@defcomp EnvironmentalDemand begin
    regions = Index()
    gauges = Index()

    flowrequirementfactor = Parameter(unit="")
    naturalflows = Parameter(index=[gauges, scenarios, time],unit="1000 m^3")
    minenvironmentalflows = Variable(index=[gauges, scenarios, time],unit="1000 m^3")
    outflowsgauges = Parameter(index=[gauges, scenarios, time],unit="1000 m^3")
    balanceenvironmentalflows = Variable(index=[gauges, scenarios, time],unit="1000 m^3")
    environmentaldemand = Variable(index=[regions, scenarios, time],unit="1000 m^3")

    """
    The quantity of water demanded at each timestep
    """
    function run_timestep(p, v, d, tt)
        for gg in d.gauges
            v.minenvironmentalflows[gg, :, tt] = p.flowrequirementfactor * p.naturalflows[gg, :, tt];
            v.balanceenvironmentalflows[gg, :, tt] = p.outflowsgauges[gg, :, tt] - v.minenvironmentalflows[gg, :, tt];
        end

        if config["dataset"] == "counties"
            for pp in 1:nrow(draws)
                if draws[!, :justif][pp] == "contains"
                    regionids = regionindex(draws, pp)
                    rr = findfirst(regionindex(masterregions, :) .== regionids)
                    if rr != nothing
                        v.environmentaldemand[rr, :, tt] += p.flowrequirementfactor * p.naturalflows[pp, :, tt];
                    end
                end
            end
        elseif config["dataset"] == "states"
            for pp in 1:nrow(draws)
                regionids = regionindex(draws, pp)
                rr = findfirst(regionindex(masterregions, :) .== regionids)
                if rr != nothing
                    v.environmentaldemand[rr, :, tt] += p.flowrequirementfactor * p.naturalflows[pp, :, tt];
                end
            end
        end
    end
end

"""
Add an urban component to the model.
"""
function initenvironmentaldemand(m::Model)
    environmentaldemand = add_comp!(m, EnvironmentalDemand);
    # set according to config file
    environmentaldemand[:flowrequirementfactor] = get(config, "proportionnaturalflowforenvironment", 0.)

    environmentaldemand
end

function constraintoffset_environmentalflows(m::Model)
    b = copy(addeds) # Start with direct added

    # Propogate in downstream order
    for hh in 1:numgauges
        gg = vertex_index(downstreamorder[hh])
        gauge = downstreamorder[hh].label
        for upstream in out_neighbors(wateridverts[gauge], waternet)
            b[gg, :, :] += DOWNSTREAM_FACTOR * b[vertex_index(upstream, waternet), :, :]
        end
    end

    function generate(gg, ss, tt)
        (config["proportionnaturalflowforenvironment"])*b[gg, ss, tt]
    end

    hallsingle(m, :WaterNetwork, :outflows, generate)
end
