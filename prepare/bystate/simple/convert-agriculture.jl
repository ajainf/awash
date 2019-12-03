include("convertlib.jl")

## Master data
config = Dict{Symbol, Any}()
config[:source] = "counties"
config[:sourceid] = :FIPS
config[:target] = "states"
config[:targetid] = :ST
config[:masterfile] = "data/global/counties.csv"
config[:mastersourceid] = :fips
config[:mastertargetid] = :state
config[:forcematching] = false

function translate(column, values)
    if in(column, [:FIPS, :FID, :County, :Total_Agriculture_Demand])
        nothing
    elseif column == :State
        values[1]
    else
        if typeof(values[1]) <: AbstractString
            values = map(x -> ismatch(r"^[-+]?[0-9]*\.?[0-9]+$", x) ? parse(Float64, x) : 0, values)
        end
        sum(map(x -> isnan.(x) ? 0 : x, dropna(values)))
    end
end

converttable("agriculture/allyears/Master_Spreadsheet_All.csv", config, translate)

## ERS data
config = Dict{Symbol, Any}()
config[:source] = "counties"
config[:sourceid] = :FIPS
config[:target] = "states"
config[:targetid] = :ST
config[:masterfile] = "data/global/counties.csv"
config[:mastersourceid] = :fips
config[:mastertargetid] = :state
config[:forcematching] = false

function translate(column, values)
    if column == :FIPS
        nothing
    else
        maxcount = 0
        maxvalue = "NA"
        for value in unique(values)
            count = sum(values .== value)
            if count > maxcount
                maxcount = count
                maxvalue = value
            end
        end

        maxvalue
    end
end

converttable("agriculture/ers/reglink.csv", config, translate)

## Model coefficients
config = Dict{Symbol, Any}()
config[:source] = "counties"
config[:sourceid] = :fips
config[:target] = "states"
config[:targetid] = :state
config[:masterfile] = "data/global/counties.csv"
config[:mastersourceid] = :fips
config[:mastertargetid] = :state

function translatechunk(subdf)
    subresult = DataFrame(coef=String[], mean=Float64[], serr=Float64[])

    for coef in unique(subdf[:coef])
        if coef in ["gddoffset", "kddoffset"]
            push!(subresult, [coef, mean(subdf[subdf[:coef] .== coef, :mean]), 0.0])
        else
            means = subdf[subdf[:coef] .== coef, :mean]
            serrs = subdf[subdf[:coef] .== coef, :serr]

            # Drop NAs and NaN
            invalid = isna.(means) | isnan.(means) | isnan.(serrs)
            if sum(invalid) > 0
                means[invalid] = 0
                serrs[invalid] = Inf
            end

            invvars = 1 ./ (serrs.^2)

            poolmean = sum(means .* invvars) / sum(invvars)
            poolserr = 1 ./ sum(invvars)

            push!(subresult, [coef, poolmean, poolserr])
        end
    end

    subresult
end

for filename in readdir("../../../data/counties/agriculture/bayesian")
    chunkyconverttable("agriculture/bayesian/$filename", config, translatechunk)
end

for filename in readdir("../../../data/counties/agriculture")
    if startswith(filename, "unpooled-")
        chunkyconverttable("agriculture/$filename", config, translatechunk)
    end
end

## Other county-specific data
config = Dict{Symbol, Any}()
config[:source] = "counties"
config[:target] = "states"
config[:mastersourcefile] = "data/global/counties.csv"
config[:mastertargetfile] = "data/global/states.csv"
config[:mastersourceid] = :state
config[:mastertargetid] = :state

for filename in readdir("../../../data/counties/agriculture/edds")
    orderedconverttable("agriculture/edds/$filename", config, (column, values) -> mean(dropna(values)))
end

function translate(column, values)
    if column == :FIPS || column == :fips
        :targetid
    else
        sum(dropna(values))
    end
end

orderedconverttable("agriculture/irrigatedareas.csv", config, translate)
orderedconverttable("agriculture/rainfedareas.csv", config, translate)
orderedconverttable("agriculture/knownareas.csv", config, translate)
orderedconverttable("agriculture/totalareas.csv", config, translate)

mirrorfile("agriculture/nationals.csv", config)

## Return flows

using Statistics, CSV

df = readtable(joinpath(todata, "data/counties/returnflows/returnfracs.csv"))
regioncol = :STATE
outpath = joinpath(todata, "data/states/returnflows/returnfracs.csv")

function regionaverage(df, regioncol, outpath)
    columns = Dict{Symbol, Any}()
    dropcols = []
    for region in unique(df[!, regioncol])
        if ismissing(region)
            continue
        end
        println(region)
        subdf = df[.!ismissing.(df[!, regioncol]) .& (df[!, regioncol] .== region), :]

        for name in names(subdf)
            println(name)
            if subdf[!, name] isa Vector{Float64} || subdf[!, name] isa Vector{Union{Float64, Missing}} || subdf[!, name] isa Vector{Int64} || subdf[!, name] isa Vector{Union{Missing, Int64}}
                value = mean(skipmissing(subdf[!, name]))
            elseif all(subdf[!, name] .== subdf[1, name])
                value = subdf[1, name]
            else
                push!(dropcols, name)
                continue
            end

            if !in(name, keys(columns))
                columns[name] = Vector{Union{typeof(value), Missing}}([])
            end
            push!(columns[name], value)
        end
    end

    dropcols = unique(dropcols)

    result = DataFrame()
    for name in filter(name -> !in(name, dropcols), names(df))
        result[!, name] = columns[name]
    end

    CSV.write(outpath, result)
end

## Monthly crop demands
using Statistics, CSV

states = CSV.read(joinpath(todata, "data/global/states.csv"))

df = CSV.read(joinpath(todata, "data/counties/demand/agmonthshares.csv"))
outpath = joinpath(todata, "data/states/demand/agmonthshares.csv")

columns = Dict{Symbol, Any}(:ST => [])
for stfips in unique(floor.(df[!, :fips] / 1000))
    region = states[states[:fips] .== stfips, :state]
    if (length(region) == 0)
        println(stfips)
        continue
    end
    println(region)
    subdf = df[floor.(df[!, :fips] / 1000) .== stfips, :]

    for name in names(subdf)
        if (name == :fips)
            continue
        end
        value = mean(subdf[!, name])

        if !in(name, keys(columns))
            columns[name] = Vector{Float64}()
        end
        push!(columns[name], value)
    end

    push!(columns[:ST], region)
end

result = DataFrame()
for name in names(df)
    if name == :fips
        result[!, :ST] = columns[:ST]
    else
        result[!, name] = columns[name]
    end
end

CSV.write(outpath, result)

