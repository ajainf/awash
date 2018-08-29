## Reservoir data library
#
# Functions to handle reservoirs.

using DataFrames
include("datastore.jl")

"""
Return a DataFrame containing `collection` and `colid` fields matching those in
the Water Network.

Any additional columns can be provided, to be used by other components.

Rows may be excluded, to represent that a given reservoir should be modeled as a
stream at the specified timestep (in months).
"""
function getreservoirs(config::Union{Dict{Any,Any},Dict{AbstractString,Any}})
    if in("dataset", keys(config))
        dataset = config["dataset"]
    else
        warn("Config does not contain dataset; assuming `counties`.")
        dataset = "counties"
    end

    if dataset == "three"
        DataFrame(collection="three", colid=2)
    else
        try
            reservoirs = CSV.read(loadpath("reservoirs/allreservoirs.csv"), types=[String, String, Union{Float64, Missing}, Float64, Float64, Union{Float64, Missing}, Float64, String], missingstring="NA")
        catch
            reservoirs = CSV.read(loadpath("reservoirs/allreservoirs.csv"), types=[String, String, Union{Float64, Missing}, Float64, Float64, Union{Float64, Missing}, Float64, String], missingstring="\"NA\"")
        end
        if get(config, "filterstate", nothing) != nothing
            reservoirs = reservoirs[floor(parse.(Int64, reservoirs[:fips]) / 1000) .== parse(Int64, config["filterstate"]), :]
        end

        reservoirs
    end
end
