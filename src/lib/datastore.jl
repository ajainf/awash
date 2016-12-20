"""
Return the full path to a standard data file.
"""
function datapath(filename)
    dataset = get(config, "dataset", "counties")
    if startswith(filename, "agriculture")
        joinpath(dirname(@__FILE__), "../../data/$dataset/$filename")
    else
        joinpath(dirname(@__FILE__), "../../data/$filename")
    end
end

"""
Return the normal data suffix
"""
function getsuffix()
    suffix = (get(config, "filterstate", nothing) != nothing ? "-$(config["filterstate"])" : "")
    if config["dataset"] == "dummy"
        suffix = "-dummy";
    elseif config["dataset"] == "three"
        suffix = "-three";
    end

    suffix
end

"""
Retrieve only the part of a file within filterstate, if one is set.
"""
function getfilteredtable(datapath, fipscol=:FIPS)
    recorded = readtable(datapath(datapath))
    if get(config, "filterstate", nothing) != nothing
        recorded = recorded[find(floor(recorded[fipscol]/1e3) .== parse(Int64,config["filterstate"])), :]
    end
    recorded
end

"""
Either get data from a cached source, or produce it by a fallback generation
Does not save fallback generation: for saving, use cache_store
"""
function cached_fallback(filename, generate)
    suffix = getsuffix()
    confighash = hash(config) # make specific to configs
    try
        if isfile(datapath("$filename$suffix-$confighash.jld"))
            return deserialize(open(datapath("$filename$suffix-$confighash.jld")))
        elseif isfile(datapath("$filename$suffix.jld"))
            return deserialize(open(datapath("$filename$suffix.jld")))
        end
    end

    generate()
end

"""
Save data to later be restored using cached_fallback or deserialize
"""
function cached_store(filename, object, usehash=true)
    suffix = getsuffix()
    if usehash
        confighash = hash(config) # make specific to configs
        fp = open(datapath("$filename$suffix-$confighash.jld"), "w")
        serialize(fp, object)
        close(fp)
    else
        fp = open(datapath("$filename$suffix.jld"), "w")
        serialize(fp, object)
        close(fp)
    end
end

"""
Dataset descriptions used by ncload.
Dictionary specifies the local filename, excluding the extension, the NetCDF link, the CSV link, and the column dimension.
"""
ncdatasets = Dict{ASCIIString, Dict{ASCIIString, Any}}("weather" => Dict{ASCIIString, Any}("filename" => "VIC_WB", "ncurl" => "https://www.dropbox.com/s/j7fi1kgw461icwa/VIC_WB.nc?dl=1", "csvurl" => "https://www.dropbox.com/s/rhuvdi7iu5wa3tl/VIC_WB.csv?dl=1", "csvcoldim" => "county", "nccrc32" => 0x468f7994, "csvcrc" => 0xcefed8fe),
                                                               "runoff" => Dict{ASCIIString, Any}("filename" => "contributing_runoff_by_gage", "ncurl" => "https://www.dropbox.com/s/itw2dzdv0051acw/contributing_runoff_by_gage.nc?dl=1", "csvurl" => "https://www.dropbox.com/s/fq8vrh4lgoewi40/contributing_runoff_by_gage.csv?dl=1", "csvcoldim" => "gage", "nccrc32" => 0x78f4dc8d, "csvcrc32" => 0x78f4dc8d))
# CRC from julia -e "using CRC; main(ARGS)" (uses CRC_32)
# Currently CRCs are ignored

if Pkg.installed("NetCDF") != nothing
    include("datastore-netcdf.jl")
else
    include("datastore-nonetcdf.jl")
end
