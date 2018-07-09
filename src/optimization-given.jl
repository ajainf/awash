## Known Demand Optimization Model construction
#
# Provides `optimization_given`, which produces a linear programming
# model where demands are exogenous.

using Mimi
using OptiMimi

include("world.jl")
if config["dataset"] == "three"
    include("weather-three.jl")
else
    include("weather.jl")
end

redogwwo = !isfile(cachepath("partialhouse2$suffix.jld"))

include("WaterDemand.jl")
include("WaterNetwork.jl")
include("Allocation.jl")
include("ReturnFlows.jl")
include("Reservoir.jl")
include("Groundwater.jl")
include("EnvironmentalDemand.jl")
include("WaterRight.jl")

function optimization_given(allowgw=false, allowreservoirs=true, demandmodel=nothing, waterrightconst=nothing)
    # First solve entire problem in a single timestep
    m = newmodel();

    # Add all of the components
    waterdemand = initwaterdemand(m); # dep. Agriculture, PopulationDemand
    allocation = initallocation(m); # dep. WaterDemand, optimization (withdrawals)
    if allowreservoirs
        reservoir = initreservoir(m); # Allocation or optimization-only
    end
    returnflows = initreturnflows(m); # dep. Allocation
    waternetwork = initwaternetwork(m); # dep. ReturnFlows
    aquifer = initaquifer(m);
    environmentaldemand = initenvironmentaldemand(m); # dep. WaterNetwork
    waterright = initwaterright(m); # dep. Allocation


    # Only include variables needed in constraints and parameters needed in optimization

    paramcomps = [:Allocation, :Allocation, :Allocation, :Allocation]
    parameters = [:quarterwaterfromsupersource, :waterfromsupersource, :withdrawals, :returns]

    constcomps = [:WaterNetwork, :Allocation, :Allocation]
    constraints = [:outflows, :balance, :returnbalance]

    if allowgw
        # Include groundwater
        paramcomps = [paramcomps; :Allocation]
        parameters = [parameters; :waterfromgw]
    end

    if allowreservoirs
        # Include reservoir logic
        paramcomps = [paramcomps; :Reservoir]
        parameters = [parameters; :captures]

        constcomps = [constcomps; :Reservoir; :Reservoir]
        constraints = [constraints; :storagemin; :storagemax]
    end

    if waterrightconst == "SW"
        constcomps = [constcomps; :WaterRight]
        constraints = [constraints; :swtotal]
    elseif waterrightconst == "GW"
        constcomps = [constcomps; :WaterRight]
        constraints = [constraints; :gwtotal]
    elseif waterrightconst == "SWGW"
        constcomps = [constcomps; :WaterRight; :WaterRight]
        constraints = [constraints; :swtotal; :gwtotal]
    end

    ## Constraint definitions:
    # outflows is the water in the stream
    # swbalance is the demand minus supply
    # Reservoir storage cannot be <min or >max

    house = LinearProgrammingHouse(m, paramcomps, parameters, constcomps, constraints, Dict(:quarterwaterfromsupersource, :waterfromsupersource, :storagemin => :storage, :storagemax => :storage));

    # Minimize supersource_cost + withdrawal_cost + suboptimallevel_cost
    if allowgw
        setobjective!(house, -varsum(grad_allocation_cost_waterfromgw(m)))
    end
    setobjective!(house, -varsum(grad_allocation_cost_withdrawals(m)))
    setobjective!(house, -.5 * hall_relabel(varsum(grad_allocation_cost_waterfromsupersource(m)), :waterfromsupersource, :Allocation, :quarterwaterfromsupersource))
    setobjective!(house, -varsum(grad_allocation_cost_waterfromsupersource(m)))
    if allowreservoirs
        setobjective!(house, -varsum(grad_reservoir_cost_captures(m)))
    end

    # Constrain that the water in the stream is non-negative, or superior to environmental requirement
    # That is, outflows + runoff > envrequirement, or -outflows < runoff - envrequirement
    if redogwwo
        gwwo = grad_waternetwork_outflows_withdrawals(m);
        serialize(open(cachepath("partialhouse$suffix.jld"), "w"), gwwo);
        cwro = constraintoffset_waternetwork_outflows(m);
        serialize(open(cachepath("partialhouse2$suffix.jld"), "w"), cwro);
        if allowreservoirs
            gror = grad_reservoir_outflows_captures(m);
            serialize(open(cachepath("partialhouse-gror$suffix.jld"), "w"), gror);
        end
    else
        gwwo = deserialize(open(cachepath("partialhouse$suffix.jld"), "r"));
        #cwro = deserialize(open(cachepath("partialhouse2$suffix.jld"), "r"));
        cwro = constraintoffset_waternetwork_outflows(m);
        if allowreservoirs
            if isfile(cachepath("partialhouse-gror$suffix.jld"))
                gror = deserialize(open(cachepath("partialhouse-gror$suffix.jld"), "r"));
            else
                gror = grad_reservoir_outflows_captures(m);
            end
        end
    end

    # Specify the components affecting outflow: withdrawals, returns, captures
    setconstraint!(house, -room_relabel_parameter(gwwo, :withdrawals, :Allocation, :withdrawals)) # +
    setconstraint!(house, room_relabel_parameter(gwwo - grad_waternetwork_immediateoutflows_withdrawals(m), :withdrawals, :Allocation, :returns)) # -
    if allowreservoirs
        setconstraint!(house, -gror) # +
    end
    # Specify that these can at most equal the cummulative runoff
    if get(config, "proportionnaturalflowforenvironment", 0.) > 0.
        setconstraintoffset!(house, cwro - constraintoffset_environmentalflows(m)) # +
    else
        setconstraintoffset!(house, cwro)
    end

    # Constrain swdemand < swsupply, or recorded < supersource + withdrawals, or -supersource - withdrawals < -recorded
    setconstraint!(house, -room_relabel(grad_allocation_balance_waterfromsupersource(m), :waterfromsupersource, :Allocation, :quarterwaterfromsupersource)) # -
    setconstraint!(house, -grad_allocation_balance_waterfromsupersource(m)) # -
    if allowgw
        setconstraint!(house, -grad_allocation_balance_waterfromgw(m)) # -
    end
    setconstraint!(house, -grad_allocation_balance_withdrawals(m)) # -
    setconstraintoffset!(house, -constraintoffset_allocation_recordedtotal(m, allowgw, demandmodel)) # -

    recorded = getfilteredtable("extraction/USGS-2010.csv")
    setupper!(house, LinearProgrammingHall(:Allocation, :quarterwaterfromsupersource, recorded[:, :TO_SW]))

    # Constraint returnbalance < 0, or returns - waterreturn < 0, or returns < waterreturn
    # `waterreturn` is by region, and is then distributed into canals as `returns`
    # `returns` must be less than `waterreturn`, so that additional water doesn't appear in streams
    setconstraint!(house, grad_allocation_returnbalance_returns(m)) # +
    if config["dataset"] == "three"
        setconstraintoffset!(house, LinearProgrammingHall(:Allocation, :returnbalance, [0., 0., 0., 0., 0., 0., 0., 0., 0.]))
    else
        setconstraintoffset!(house, -hall_relabel(grad_waterdemand_totalreturn_totalirrigation(m) * values_waterdemand_recordedirrigation(m, allowgw, demandmodel) +
                                                  grad_waterdemand_totalreturn_domesticuse(m) * values_waterdemand_recordeddomestic(m) +
                                                  grad_waterdemand_totalreturn_industrialuse(m) * values_waterdemand_recordedindustrial(m) +
                                                  grad_waterdemand_totalreturn_thermoelectricuse(m) * values_waterdemand_recordedthermoelectric(m) +
                                                  grad_waterdemand_totalreturn_livestockuse(m) * values_waterdemand_recordedlivestock(m),
        :totalreturn, :Allocation, :returnbalance)) # +
    end

    if allowreservoirs
        # Reservoir constraints:
        # initial storage and evaporation have been added
        # min storage is reservoir min
        # max storage is reservoir max

        # Constrain storage > min or -storage < -min
        setconstraint!(house, -room_relabel(grad_reservoir_storage_captures(m), :storage, :Reservoir, :storagemin)) # -
        setconstraintoffset!(house, hall_relabel(-constraintoffset_reservoir_storagecapacitymin(m)+constraintoffset_reservoir_storage0(m), :storage, :Reservoir, :storagemin))

        # Constrain storage < max
        setconstraint!(house, room_relabel(grad_reservoir_storage_captures(m), :storage, :Reservoir, :storagemax)) # +
        setconstraintoffset!(house, hall_relabel(constraintoffset_reservoir_storagecapacitymax(m)-constraintoffset_reservoir_storage0(m), :storage, :Reservoir, :storagemax))

        setlower!(house, LinearProgrammingHall(:Reservoir, :captures, ones(numreservoirs * numsteps) * -Inf))
    end

    # Water rights constraints: swwithdrawals < swwaterights | gwwithdrawals < gwwaterrights
    if waterrightconst == "SW"
        setconstraint!(house, room_relabel_parameter(grad_waterright_swtotal_withdrawals(m), :swtimestep, :Allocation, :withdrawals)) # +
        setconstraintoffset!(house, constraintoffset_waterright_swrighttotal(m)) # +
    elseif waterrightconst == "GW"
        setconstraint!(house, room_relabel_parameter(grad_waterright_gwtotal_waterfromgw(m), :gwtimestep, :Allocation, :waterfromgw))
        setconstraintoffset!(house, constraintoffset_waterright_gwrighttotal(m)) # +
    elseif waterrightconst == "SWGW"
        setconstraint!(house, room_relabel_parameter(grad_waterright_swtotal_withdrawals(m), :swtimestep, :Allocation, :withdrawals)) # +
        setconstraintoffset!(house, constraintoffset_waterright_swrighttotal(m)) # +
        setconstraint!(house, room_relabel_parameter(grad_waterright_gwtotal_waterfromgw(m), :gwtimestep, :Allocation, :waterfromgw))
        setconstraintoffset!(house, constraintoffset_waterright_gwrighttotal(m)) # +
    end




    # Clean up

    house.b[isnan.(house.b)] = 0
    house.b[house.b .== Inf] = 1e9
    house.b[house.b .== -Inf] = -1e9
    house.f[isnan.(house.f)] = 0
    house.f[house.f .== Inf] = 1e9
    house.f[house.f .== -Inf] = -1e9

    ri, ci, vv = findnz(house.A)
    for ii in find(isnan.(vv))
        house.A[ri[ii], ci[ii]] = vv[ii]
    end
    for ii in find(.!isfinite.(vv))
        house.A[ri[ii], ci[ii]] = 1e9
    end

    house
end

"""
Save the results for simulation runs
"""
function save_optimization_given(house::LinearProgrammingHouse, sol, allowgw=false, allowreservoirs=true)
    # The size of each optimized parameter
    varlens = varlengths(house.model, house.paramcomps, house.parameters)
    varlens = [varlens; 0] # Add dummy, so allowgw can always refer to 1:4

    # Save into serialized files
    serialize(open(datapath("extraction/withdrawals$suffix.jld"), "w"), reshape(sol.sol[varlens[1:2]+1:sum(varlens[1:3])], numcanals, numsteps))
    serialize(open(datapath("extraction/returns$suffix.jld"), "w"), reshape(sol.sol[sum(varlens[1:3])+1:sum(varlens[1:4])], numcanals, numsteps))

    if allowgw
        serialize(open(datapath("extraction/waterfromgw$suffix.jld"), "w"), reshape(sol.sol[sum(varlens[1:4])+1:sum(varlens[1:5])], numcounties, numsteps))
    elseif isfile(datapath("extraction/waterfromgw$suffix.jld"))
        rm(datapath("extraction/waterfromgw$suffix.jld"))
    end

    if allowreservoirs
        serialize(open(datapath("extraction/captures$suffix.jld"), "w"), reshape(sol.sol[sum(varlens[1:4+allowgw])+1:end], numreservoirs, numsteps))
    elseif isfile(datapath("extraction/captures$suffix.jld"))
        rm(datapath("extraction/captures$suffix.jld"))
    end
end
