export GenericWaterModel, build_generic_model, ids

""
abstract type AbstractWaterFormulation end

"""
```
type GenericWaterModel{T<:AbstractWaterFormulation}
    model::JuMP.Model
    data::Dict{String,Any}
    setting::Dict{String,Any}
    solution::Dict{String,Any}
    var::Dict{Symbol,Any} # model variable lookup
    ref::Dict{Symbol,Any} # reference data
    ext::Dict{Symbol,Any} # user extentions
end
```
where

* `data` is the original data, usually from reading in a `.inp` file,
* `setting` usually looks something like `Dict("output" => Dict("flows" => true))`, and
* `ref` is a place to store commonly-used precomputed data from the data dictionary,
    primarily for converting datatypes, filtering deactivated components, and storing
    system-wide values that need to be computed globally. See `build_ref(data)` for further details.

Methods on `GenericWaterModel` for defining variables and adding constraints should

* work with the `ref` dict, rather than the original `data` dict,
* add them to `model::JuMP.Model`, and
* follow the conventions for variable and constraint names.
"""
mutable struct GenericWaterModel{T<:AbstractWaterFormulation}
    model::Model

    data::Dict{String, Any}
    setting::Dict{String, Any}
    solution::Dict{String, Any}

    ref::Dict{Symbol, Any} # data reference data
    var::Dict{Symbol, Any} # JuMP variables
    con::Dict{Symbol, Any} # JuMP constraint references
    cnw::Int # current network index value

    # Extensions should define a type to hold information particular to
    # their functionality, and store an instance of the type in this
    # dictionary keyed on an extension-specific symbol.
    ext::Dict{Symbol, Any}
end

function GenericWaterModel(data::Dict{String, Any}, T::DataType;
                           ext = Dict{String, Any}(),
                           setting = Dict{String,Any}(),
                           solver = JuMP.UnsetSolver())
    ref = build_ref(data)
    var = Dict{Symbol, Any}(:nw => Dict{Int, Any}())
    con = Dict{Symbol, Any}(:nw => Dict{Int, Any}())
    cnw = minimum(keys(ref[:nw]))

    for nw_id in keys(ref[:nw])
        var[:nw][nw_id] = Dict{Symbol, Any}()
        con[:nw][nw_id] = Dict{Symbol, Any}()
    end

    wm = GenericWaterModel{T}(Model(solver = solver), data, setting,
                              Dict{String, Any}(), ref, var, con, cnw, ext)

    return wm
end

function build_generic_model(data::Dict{String, Any}, model_constructor, post_method; kwargs...)
    wm = model_constructor(data; kwargs...)
    post_method(wm)
    return wm
end

function build_generic_model(path::String, model_constructor, post_method; kwargs...)
    data = WaterModels.parse_file(path)
    return build_generic_model(data, model_constructor, post_method; kwargs...)
end

function run_generic_model(path::String, model_constructor, solver, post_method; solution_builder = get_solution, kwargs...)
    wm = build_generic_model(path, model_constructor, post_method; kwargs...)
    return solve_generic_model(wm, solver; solution_builder = solution_builder)
end

function solve_generic_model(wm::GenericWaterModel, solver; solution_builder = get_solution)
    setsolver(wm.model, solver)
    status, solve_time = solve(wm)
    return build_solution(wm, status, solve_time; solution_builder = solution_builder)
end

function JuMP.setsolver(wm::GenericWaterModel, solver::MathProgBase.AbstractMathProgSolver)
    setsolver(wm.model, solver)
end

function JuMP.solve(wm::GenericWaterModel)
    status, solve_time, solve_bytes_alloc, sec_in_gc = @timed solve(wm.model)
    #status, solve_time, solve_bytes_alloc, sec_in_gc = @timed solve(wm.model, relaxation = true)

    try
        solve_time = getsolvetime(wm.model)
    catch
        warn(LOGGER, "There was an issue with getsolvetime() on the solver, falling back on @timed.  This is not a rigorous timing value.");
    end

    return status, solve_time
end

"""
Returns a dict that stores commonly-used, precomputed data from of the data dictionary,
primarily for converting data types, filtering out deactivated components, and storing
system-wide values that need to be computed globally.

Some of the common keys include:

* `:max_flow` (see `max_flow(data)`),
* `:connection` -- the set of connections that are active in the network (based on the component status values),
* `:pipe` -- the set of connections that are pipes (based on the component type values),
* `:short_pipe` -- the set of connections that are short pipes (based on the component type values),
* `:compressor` -- the set of connections that are compressors (based on the component type values),
* `:valve` -- the set of connections that are valves (based on the component type values),
* `:control_valve` -- the set of connections that are control valves (based on the component type values),
* `:resistor` -- the set of connections that are resistors (based on the component type values),
* `:parallel_connections` -- the set of all existing connections between junction pairs (i,j),
* `:all_parallel_connections` -- the set of all existing and new connections between junction pairs (i,j),
* `:junction_connections` -- the set of all existing connections of junction i,
* `:junction_ne_connections` -- the set of all new connections of junction i,
* `junction[degree]` -- the degree of junction i using existing connections (see `add_degree`)),
* `junction[all_degree]` -- the degree of junction i using existing and new connections (see `add_degree`)),
* `connection[pd_min,pd_max]` -- the max and min square pressure difference (see `add_pd_bounds_swr`)),

If `:ne_connection` does not exist, then an empty reference is added
If `status` does not exist in the data, then 1 is added
If `construction cost` does not exist in the `:ne_connection`, then 0 is added
"""
function build_ref(data::Dict{String, Any})
    refs = Dict{Symbol, Any}()
    nws = refs[:nw] = Dict{Int, Any}()

    if data["multinetwork"]
        nws_data = data["nw"]
    else
        nws_data = Dict{String, Any}("0" => data)
    end

    for (n, nw_data) in nws_data
        nw_id = parse(Int, n)
        ref = nws[nw_id] = Dict{Symbol, Any}()

        for (key, item) in nw_data
            ref[Symbol(key)] = item
        end
    end

    return refs
end

ids(wm::GenericWaterModel, key::Symbol) = ids(wm, wm.cnw, key)
ids(wm::GenericWaterModel, n::Int, key::Symbol) = keys(wm.ref[:nw][n][key])

#" Set the solver "
#function JuMP.setsolver(wm::GenericWaterModel, solver::MathProgBase.AbstractMathProgSolver)
#    setsolver(wm.model, solver)
#end
#
#" Do a solve of the problem "
#function JuMP.solve(wm::GenericWaterModel)
#    status, solve_time, solve_bytes_alloc, sec_in_gc = @timed solve(wm.model)
#
#    try
#        solve_time = getsolvetime(wm.model)
#    catch
#        warn("there was an issue with getsolvetime() on the solver, falling back on @timed.  This is not a rigorous timing value.");
#    end
#
#    return status, solve_time
#end
#
#""
#function run_generic_model(file::String, model_constructor, solver, post_method; kwargs...)
#    data = WaterModels.parse_file(file)
#    return run_generic_model(data, model_constructor, solver, post_method; kwargs...)
#end
#
#""
#function run_generic_model(data::Dict{String,Any}, model_constructor, solver, post_method; solution_builder = get_solution, kwargs...)
#    wm = build_generic_model(data, model_constructor, post_method; kwargs...)
#    solution = solve_generic_model(wm, solver; solution_builder = solution_builder)
#    return solution
#end
#
#""
#function build_generic_model(file::String,  model_constructor, post_method; kwargs...)
#    data = WaterModels.parse_file(file)
#    return build_generic_model(data, model_constructor, post_method; kwargs...)
#end
#
#
#""
#function build_generic_model(data::Dict{String,Any}, model_constructor, post_method; kwargs...)
#    wm = model_constructor(data; kwargs...)
#    post_method(wm)
#    return wm
#end
#
#""
#function solve_generic_model(wm::GenericWaterModel, solver; solution_builder = get_solution)
#    setsolver(wm.model, solver)
#    status, solve_time = solve(wm)
#    return build_solution(wm, status, solve_time; solution_builder = solution_builder)
#end
#
#"""
#Returns a dict that stores commonly used pre-computed data from of the data dictionary,
#primarily for converting data-types, filtering out deactivated components, and storing
#system-wide values that need to be computed globally.
#
#Some of the common keys include:
#
#* `:max_flow` (see `max_flow(data)`),
#* `:connection` -- the set of connections that are active in the network (based on the component status values),
#* `:pipe` -- the set of connections that are pipes (based on the component type values),
#* `:short_pipe` -- the set of connections that are short pipes (based on the component type values),
#* `:compressor` -- the set of connections that are compressors (based on the component type values),
#* `:valve` -- the set of connections that are valves (based on the component type values),
#* `:control_valve` -- the set of connections that are control valves (based on the component type values),
#* `:resistor` -- the set of connections that are resistors (based on the component type values),
#* `:parallel_connections` -- the set of all existing connections between junction pairs (i,j),
#* `:all_parallel_connections` -- the set of all existing and new connections between junction pairs (i,j),
#* `:junction_connections` -- the set of all existing connections of junction i,
#* `:junction_ne_connections` -- the set of all new connections of junction i,
#* `junction[degree]` -- the degree of junction i using existing connections (see `add_degree`)),
#* `junction[all_degree]` -- the degree of junction i using existing and new connections (see `add_degree`)),
#* `connection[pd_min,pd_max]` -- the max and min square pressure difference (see `add_pd_bounds_swr`)),
#
#If `:ne_connection` does not exist, then an empty reference is added
#If `status` does not exist in the data, then 1 is added
#If `construction cost` does not exist in the `:ne_connection`, then 0 is added
#"""
#function build_ref(data::Dict{String,Any})
#    # Do some robustness on the data to add missing fields
#    # add_default_data(data)
#    add_default_status(data)
#    # add_default_construction_cost(data)
#
#    ref = Dict{Symbol,Any}()
#    for (key, item) in data
#        if isa(item, Dict)
#            item_lookup = Dict([(parse(k), v) for (k,v) in item])
#            ref[Symbol(key)] = item_lookup
#        else
#            ref[Symbol(key)] = item
#        end
#    end
#
#    # filter turned off stuff
#    ref[:connection] = filter((i, connection) -> connection["status"] == "open" && connection["f_junction"] in keys(ref[:junction])&& connection["t_junction"] in keys(ref[:junction]) , ref[:connection])
#    # ref[:ne_connection] = filter((i, connection) -> connection["status"] == 1 && connection["f_junction"] in keys(ref[:junction]) && connection["t_junction"] in keys(ref[:junction]), ref[:ne_connection])
#
#    # compute the maximum flow
#    # max_flow = calc_max_flow(data)
#    max_flow = 10^6;
#    ref[:max_flow] = max_flow
#
#    # create some sets based on connection types
#    ref[:pipe] = filter((i, connection) -> connection["type"] == "pipe", ref[:connection])
#    # ref[:short_pipe] = filter((i, connection) -> connection["type"] == "short_pipe", ref[:connection])
#    # ref[:compressor] = filter((i, connection) -> connection["type"] == "compressor", ref[:connection])
#    ref[:pump] = filter((i, connection) -> connection["type"] == "pump", ref[:connection])
#    ref[:valve] = filter((i, connection) -> connection["type"] == "valve", ref[:connection])
#    ref[:control_valve] = filter((i, connection) -> connection["type"] == "control_valve", ref[:connection])
#    # ref[:resistor] = filter((i, connection) -> connection["type"] == "resistor", ref[:connection])
#
#    # ref[:ne_pipe] = filter((i, connection) -> connection["type"] == "pipe", ref[:ne_connection])
#    # ref[:ne_compressor] = filter((i, connection) -> connection["type"] == "compressor", ref[:ne_connection])
#
#
#    # collect all the parallel connections and connections of a junction
#    # These are split by new connections and existing connections
#    ref[:parallel_connections] = Dict()
#    # ref[:all_parallel_connections] = Dict()
#    # for entry in [ref[:connection]; ref[:ne_connection]]
#    for entry in [ref[:connection]]
#        for (idx, connection) in entry
#            i = string(connection["f_junction"])
#            j = string(connection["t_junction"])
#            ref[:parallel_connections][(parse(min(i,j)), parse(max(i,j)))] = []
#            # ref[:all_parallel_connections][(min(i,j), max(i,j))] = []
#        end
#    end
#
#    ref[:junction_connections] = Dict(i => [] for (i,junction) in ref[:junction])
#    # ref[:junction_ne_connections] = Dict(i => [] for (i,junction) in ref[:junction])
#
#    for (idx, connection) in ref[:connection]
#        i = string(connection["f_junction"])
#        j = string(connection["t_junction"])
#        push!(ref[:junction_connections][parse(i)], idx)
#        push!(ref[:junction_connections][parse(j)], idx)
#        push!(ref[:parallel_connections][(parse(min(i,j)), parse(max(i,j)))], idx)
#        # push!(ref[:all_parallel_connections][(min(i,j), max(i,j))], idx)
#    end
#
#    # for (idx,connection) in ref[:ne_connection]
#    #     i = connection["f_junction"]
#    #     j = connection["t_junction"]
#    #     push!(ref[:junction_ne_connections][i], idx)
#    #     push!(ref[:junction_ne_connections][j], idx)
#    #     push!(ref[:all_parallel_connections][(min(i,j), max(i,j))], idx)
#    # end
#
#    add_degree(ref)
#    add_hd_bounds(ref)
#    add_resistance_pipe(ref)
#    return ref
#end
#
## "Just make sure there is an empty set for new connections if it does not exist"
## function add_default_data(data :: Dict{String,Any})
##     if !haskey(data, "ne_connection")
##         data["ne_connection"] = []
##     end
## end
