## Water Network Construction
#
# Load and connect the water network.

using Mimi
using Graphs
using DataFrames
using RData
using Serialization

include("lib/waternet.jl")

if !(@isdefined RegionNetwork)
    RegionNetwork{R, E} = IncidenceList{R, E}
end

OverlaidRegionNetwork = RegionNetwork{ExVertex, ExEdge}

filtersincludeupstream = false # true to include all upstream nodes during a filter

# Water network has OUT nodes to UPSTREAM

empty_extnetwork() = OverlaidRegionNetwork(true, ExVertex[], 0, Vector{Vector{ExEdge}}())

if isfile(cachepath("waternet$suffix.jld"))
    println("Loading from saved water network...")

    # The Graph object
    waternet = deserialize(open(cachepath("waternet$suffix.jld"), "r"));
    # Dictionary from gaugeid to vertex
    wateridverts = deserialize(open(cachepath("wateridverts$suffix.jld"), "r"));
    # DataFrame with information about canals, including fips and gaugeid
    draws = deserialize(open(cachepath("waterdraws$suffix.jld"), "r"));
elseif isfile(datapath("waternet/waternet$suffix.jld"))
    # The Graph object
    waternet = deserialize(open(datapath("waternet/waternet$suffix.jld"), "r"));
    # Dictionary from gaugeid to vertex
    wateridverts = deserialize(open(datapath("waternet/wateridverts$suffix.jld"), "r"));
    # DataFrame with information about canals, including fips and gaugeid
    draws = deserialize(open(datapath("waternet/waterdraws$suffix.jld"), "r"));
else
    # Load the network of counties
    if config["dataset"] == "three"
        waternetdata = Dict{Any, Any}("network" => DataFrame(collection=repeat(["three"], 3), colid=1:3, lat=repeat([0], 3), lon=-1:1, nextpt=[2, 3, missing], dist=repeat([1], 3)))
        drawsdata = Dict{Any, Any}("draws" => DataFrame(fips=1:3, source=1:3, justif=repeat(["contains"], 3), downhill=repeat([0], 3), exdist=repeat([0.0], 3)))
    elseif config["dataset"] == "dummy"
        waternetdata = load(datapath("waternet/dummynet.RData"));
        drawsdata = load(datapath("waternet/dummydraws.RData"));
    else
        waternetdata = load(loadpath("waternet/waternet.RData"));
        drawsdata = load(loadpath("waternet/countydraws.RData"));
    end

    netdata = waternetdata["network"];
    netdata[!, :nextpt] = convert(Vector{Union{Missings.Missing, Int64}}, netdata[!, :nextpt])

    # Load the county-network connections
    draws = drawsdata["draws"];
    draws[!, :source] .= round.(Int64, draws[!, :source])
    # Label all with the node name
    draws[!, :gaugeid] .= ""
    for ii in 1:nrow(draws)
        row = draws[ii, :source]
        draws[ii, :gaugeid] = "$(netdata[row, :collection]).$(netdata[row, :colid])"
    end

    if get(config, "filterstate", nothing) != nothing
        states = round.(Int64, draws[!, :fips] / 1000)
        draws = draws[states .== parse(Int64, get(config, "filterstate", nothing)), :]

        includeds = falses(nrow(netdata))
        if filtersincludeupstream
            # Flag all upstream nodes
            chcks = draws[!, :source]
            while length(chcks) > 0
                includeds[chcks] = true

                nexts = []
                for check in chcks
                    nexts = [nexts; findall(netdata[!, :nextpt] .== check)]
                end

                chcks = nexts
            end
        else
            includeds[draws[!, :source]] .= true
        end
    else
        includeds = trues(nrow(netdata))
    end

    wateridverts = Dict{String, ExVertex}();
    waternet = empty_extnetwork();
    for row in 1:nrow(netdata)
        if !includeds[row]
            continue
        end

        nextpt = netdata[row, :nextpt]
        if ismissing.(nextpt)
            continue
        end

        thisid = "$(netdata[row, :collection]).$(netdata[row, :colid])"
        nextid = "$(netdata[nextpt, :collection]).$(netdata[nextpt, :colid])"

        if thisid == nextid
            #error("Same same!")
            netdata[row, :nextpt] = missing
            continue
        end

        if thisid in keys(wateridverts) && nextid in keys(wateridverts) &&
            wateridverts[nextid] in out_neighbors(wateridverts[thisid], waternet)
            # error("No backsies!")
            continue
        end

        if !(thisid in keys(wateridverts))
            wateridverts[thisid] = ExVertex(length(wateridverts)+1, thisid)
            add_vertex!(waternet, wateridverts[thisid])
        end

        if !(nextid in keys(wateridverts))
            wateridverts[nextid] = ExVertex(length(wateridverts)+1, nextid)
            add_vertex!(waternet, wateridverts[nextid])
        end

        add_edge!(waternet, wateridverts[nextid], wateridverts[thisid])

        #if test_cyclic_by_dfs(waternet)
        #    error("Cycles off the road!")
        #end
    end

    # Construct the network
    serialize(open(cachepath("waternet$suffix.jld"), "w"), waternet)
    serialize(open(cachepath("wateridverts$suffix.jld"), "w"), wateridverts)
    serialize(open(cachepath("waterdraws$suffix.jld"), "w"), draws)
end

# Prepare the model
downstreamorder = topological_sort_by_dfs(waternet)[end:-1:1];

gaugeorder = Vector{String}(undef, length(wateridverts))
for vertex in downstreamorder
    gaugeorder[vertex_index(vertex)] = vertex.label
end

# Flag every gauge that's a reservoir
include("lib/reservoirs.jl")
reservoirs = getreservoirs(config)

# Zero if not a reservoir, else its index
isreservoir = zeros(Int64, length(wateridverts))

for ii in 1:nrow(reservoirs)
    resid = "$(reservoirs[ii, :collection]).$(reservoirs[ii, :colid])"
    if haskey(wateridverts, resid) # Not all reservoirs in network!
        isreservoir[vertex_index(wateridverts[resid])] = ii
    end
end

# Filter county connections draws
if get(config, "filtercanals", nothing) != nothing
    if config["filtercanals"] == "direct"
        draws = draws[[findfirst(x -> x in ["contains", "up-pipe", "down-pipe"], justif) for justif in draws[!, :justif]] .> 0, :]
    else
        draws = draws[findall(draws[!, :justif] .== config["filtercanals"]),:]
    end
end
