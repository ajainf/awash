## File Caching library
#
# Provides a cache for files that only need to be loaded once.

using CSV

if !isdefined(:inputvalues)
    # Store previously opened CSVs
    const inputvalues = Dict{String, Any}()
end

"""
Get a value which can be cached as a direct result of a file.
"""
function getfilevalue(fullpath::AbstractString, name::AbstractString, process::Function)
    key = "$fullpath:$name"
    if !(key in keys(inputvalues))
        inputvalues[key] = process()
    end

    inputvalues[key]
end

function cachereadtable(fullpath::AbstractString; kwargs...)
    getfilevalue(fullpath, "*", () -> CSV.read(fullpath; kwargs...))
end

function cachereadrda(fullpath::AbstractString)
    getfilevalue(fullpath, "*", () -> FileIO.load(fullpath))
end

function clearfilecache()
    empty!(inputvalues)
end

function knowndf(filenickname::AbstractString)
    if filenickname == "exogenous-withdrawals"
        try
            getfilevalue(loadpath("extraction/USGS-2010.csv"), "filtered",
                         () -> getfilteredtable("extraction/USGS-2010.csv", types=[repmat([String], 5); Union{Missing, Int64}; repmat([Float64], 25)], missingstring="NA"))
        catch
            getfilevalue(loadpath("extraction/USGS-2010.csv"), "filtered",
                         () -> getfilteredtable("extraction/USGS-2010.csv", types=[String; Union{Missing, Int64}; repmat([Float64], 25)], missingstring="NA"))
        end
    else
        error("Unknown DataFrame $filenickname.")
    end
end
