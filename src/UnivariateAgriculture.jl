using DataFrames
using Mimi

include("lib/agriculture.jl")
include("lib/agriculture-ers.jl")

@defcomp UnivariateAgriculture begin
    regions = Index()
    unicrops = Index()

    # Optimized
    # Land area appropriated to each crop
    totalareas = Parameter(index=[regions, unicrops, time], unit="Ha")

    # Internal
    # Yield per hectare
    yield = Parameter(index=[regions, unicrops, time], unit="none")

    # Coefficient on the effects of water deficits
    irrigation_rate = Parameter(index=[regions, unicrops, time], unit="mm")

    # Computed
    # Total agricultural area
    totalareas2 = Variable(index=[regions, unicrops, time], unit="Ha") # copy of totalareas
    allagarea = Variable(index=[regions, time], unit="Ha")
    sorghumarea=Variable(index=[regions, time], unit="Ha")
    barleyarea=Variable(index=[regions, time], unit="Ha")
    # Total irrigation water (1000 m^3)
    #irrigation_ranch=Parameter(index=[regions,time],unit="1000m^3") 
    
    totalirrigation = Variable(index=[regions, time], unit="1000 m^3") 
    #totalirrigation1 = Variable(index=[regions, time], unit="1000 m^3") #crop irrigation

    # Total production: lb or bu
    yield2 = Variable(index=[regions, unicrops, time], unit="none")
    production = Variable(index=[regions, unicrops, time], unit="lborbu")
    # Total cultivation costs per crop
    opcost = Variable(index=[regions, unicrops, time], unit="\$")
    overhead=Variable(index=[regions, unicrops, time], unit="\$")
end

function run_timestep(s::UnivariateAgriculture, tt::Int)
    v = s.Variables
    p = s.Parameters
    d = s.Dimensions

    for rr in d.regions
        totalirrigation = 0.
        allagarea = 0.

        for cc in d.unicrops
            v.totalareas2[rr, cc, tt] = p.totalareas[rr, cc, tt]
            allagarea += p.totalareas[rr, cc, tt]

            # Calculate irrigation water, summed across all crops: 1 mm * Ha = 10 m^3
            totalirrigation += p.totalareas[rr, cc, tt] * p.irrigation_rate[rr, cc, tt] / 100
            
            # Calculate total production
            v.yield2[rr, cc, tt] = p.yield[rr, cc, tt]
            v.production[rr, cc, tt] = p.yield[rr, cc, tt] * p.totalareas[rr, cc, tt] * 2.47105 # convert acres to Ha

            # Calculate cultivation costs
            v.opcost[rr, cc, tt] = p.totalareas[rr, cc, tt] * uniopcost[rr,cc] * 2.47105 * config["timestep"] / 12 # convert acres to Ha
            v.overhead[rr, cc, tt] = p.totalareas[rr, cc, tt] * unioverhead[rr,cc] * 2.47105 * config["timestep"] / 12 # convert acres to Ha
        end

        v.totalirrigation[rr, tt] = totalirrigation
        #v.totalirrigation[rr,tt]=v.totalirrigation1[rr, tt]+p.irrigation_ranch[rr,tt]
        v.allagarea[rr, tt] = allagarea
    end
end

function initunivariateagriculture(m::Model)
    # precip loaded by weather.jl
    # Sum precip to a yearly level
    stepsperyear = floor(Int64, 12 / config["timestep"])
    rollingsum = cumsum(precip, 2) - cumsum([zeros(numcounties, stepsperyear) precip[:, 1:size(precip)[2] - stepsperyear]],2)

    # Match up values by FIPS
    yield = zeros(numcounties, numunicrops, numsteps)
    irrigation_rate = zeros(numcounties, numunicrops, numsteps)
    
    for cc in 1:numunicrops

        if unicrops[cc] in ["corn.co.rainfed", "corn.co.irrigated","wheat.co.rainfed", "wheat.co.irrigated"]
            #for tt in 1:numsteps
            yield[:,cc,:] = read_nareshyields(unicrops[cc])#*exp(0.0137*(2010-index2year(tt)))
            #end 
            #irrigation_rate[:,cc,:] = known_irrigationrate[unicrops[cc]]
        #elseif unicrops[cc] in ["wheat.co.rainfed", "wheat.co.irrigated"]
            #for tt in 1:numsteps
            #yield[:,cc,tt] = read_nareshyields(unicrops[cc])*exp(0.0082*(2010-index2year(tt)))
            #end 
            irrigation_rate[:,cc,:] = known_irrigationrate[unicrops[cc]]
            continue 
        end 
            
            
        # Load degree day data
        gdds = readtable(findcroppath("agriculture/edds/", unicrops[cc], "-gdd.csv"))
        kdds = readtable(findcroppath("agriculture/edds/", unicrops[cc], "-kdd.csv"))

        for rr in 1:numcounties
            if config["dataset"] == "counties"
                regionid = masterregions[rr, :fips]
            else
                regionid = masterregions[rr, :state]
            end
            if regionid in keys(agmodels[unicrops[cc]])
                thismodel = agmodels[unicrops[cc]][regionid]
                for tt in 1:numsteps
                    year = index2year(tt)
                    if year >= 1949 && year <= 2009
                        numgdds = gdds[rr, symbol("x$year")]
                        if isna(numgdds)
                            numgdds = 0
                        end

                        numkdds = kdds[rr, symbol("x$year")]
                        if isna(numkdds)
                            numkdds = 0
                        end
                    else
                        numgdds = numkdds = 0
                    end

                    water_demand = water_requirements[unicrops[cc]] * 1000
                    water_deficit = max(0., water_demand - rollingsum[rr, tt])

                    logmodelyield = thismodel.intercept + thismodel.gdds * (numgdds - thismodel.gddoffset) + thismodel.kdds * (numkdds - thismodel.kddoffset) + (thismodel.wreq / 1000) * water_deficit
                    yield[rr, cc, tt] = min(exp(logmodelyield), maximum_yields[unicrops[cc]])

                    irrigation_rate[rr, cc, tt] = unicrop_irrigationrate[unicrops[cc]] + water_deficit * unicrop_irrigationstress[unicrops[cc]] / 1000
                    irrigation_rate[:,5,:]=330.2
                end
            end
        end
    end
    yield[:,4,:]=yield[:,4,:]/2 
    yield[:,8,:]=yield[:,8,:]*1.5
    agriculture = addcomponent(m, UnivariateAgriculture)
    
    agriculture[:yield] = yield
    agriculture[:irrigation_rate] = irrigation_rate
    #irrigation_ranch=zeros(numcounties,numsteps)
    #ranch=Array(readtable(datapath("extraction/irrigation_ranch.csv"))[:,:Irrigation])
    #agriculture[:irrigation_ranch]=repeat(ranch, outer=[1, numsteps])
    
    # Load in planted area
    totalareas = getfilteredtable("agriculture/totalareas.csv")
   if isfile(datapath("../extraction/totalareas-08.jld"))
        agriculture[:totalareas]= deserialize(open(datapath("../extraction/totalareas$suffix.jld"), "r"));
    elseif isfile(datapath("../extraction/totalareas_cst-08.jld"))
        constantareas= deserialize(open(datapath("../extraction/totalareas_cst$suffix.jld"), "r"));
        agriculture[:totalareas]=repeat(constantareas,outer=[1,1,numsteps])
    else 
        
        if isempty(unicrops)
            agriculture[:totalareas] = zeros(Float64, (nrow(totalareas), 0, numsteps))
        else
            constantareas = zeros(numcounties, numunicrops)
            for cc in 1:numunicrops
                if unicrops[cc] in keys(quickstats_planted)
                    constantareas[:, cc] = read_quickstats(datapath(quickstats_planted[unicrops[cc]]))
                else
                    column = findfirst(symbol(unicrops[cc]) .== names(totalareas))
                    constantareas[:, cc] = totalareas[column] * 0.404686 # Convert to Ha
                    constantareas[isna(totalareas[column]), cc] = 0. # Replace NAs with 0, and convert to float.
                end
            end
            constantareas[:,1]= constantareas[:,1]*2.47
            constantareas[:,4]= constantareas[:,4]*2.47
            constantareas[:,6]= constantareas[:,6]/2
            constantareas[:,7]= constantareas[:,7]/2
            constantareas[:,8]= constantareas[:,8]*1.5
            agriculture[:totalareas] = repeat(constantareas, outer=[1, 1, numsteps])
    end
    end 
    agriculture
end

function grad_univariateagriculture_production_totalareas(m::Model)
    roomdiagonal(m, :UnivariateAgriculture, :production, :totalareas, (rr, cc, tt) -> m.parameters[:yield].values[rr, cc, tt] * 2.47105 * config["timestep"]/12) # Convert acres to Ha
end

function grad_univariateagriculture_totalirrigation_totalareas(m::Model)
    function generate(A, tt)
        for rr in 1:numcounties
            for cc in 1:numunicrops
                A[rr, fromindex([rr, cc], [numcounties, numunicrops])] = m.parameters[:irrigation_rate].values[rr, cc, tt] / 100
            end
        end

        return A
    end
    roomintersect(m, :UnivariateAgriculture, :totalirrigation, :totalareas, generate)
end

function grad_univariateagriculture_cost_totalareas(m::Model)
    roomdiagonal(m, :UnivariateAgriculture, :unicultivationcost, :totalareas, (rr, cc, tt) -> uniopcost[rr,cc] * 2.47105 * config["timestep"]/12) # convert acres to Ha
end

function grad_univariateagriculture_allagarea_totalareas(m::Model)
    function generate(A, tt)
        for rr in 1:numcounties
            for cc in 1:numunicrops
                A[rr, fromindex([rr, cc], [numcounties, numunicrops])] = 1.
            end
        end

        return A
    end

    roomintersect(m, :UnivariateAgriculture, :allagarea, :totalareas, generate)
end



function grad_univariateagriculture_sorghumarea_totalareas(m::Model)
    function generate(A, tt)
        for rr in 1:numcounties
            for cc in 1:numunicrops
                if unicrops[cc]=="sorghum"
                    A[rr, fromindex([rr, cc], [numcounties, numunicrops])] = 1.
                else 
                A[rr, fromindex([rr, cc], [numcounties, numunicrops])] = 0.
            end
        end

        end
        
        return A
    end

        roomintersect(m, :UnivariateAgriculture, :sorghumarea, :totalareas, generate)
end

function grad_univariateagriculture_barleyarea_totalareas(m::Model)
    function generate(A, tt)
        for rr in 1:numcounties
            for cc in 1:numunicrops
                if unicrops[cc]=="barley"
                    A[rr, fromindex([rr, cc], [numcounties, numunicrops])] = 1.
                else 
                A[rr, fromindex([rr, cc], [numcounties, numunicrops])] = 0.
            end
        end

        end
        
        return A
    end

    roomintersect(m, :UnivariateAgriculture, :barleyarea, :totalareas, generate)
end




