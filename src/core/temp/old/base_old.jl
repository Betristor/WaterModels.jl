# stuff that is universal to all water models

export
    GenericWaterModel,
    setdata, setsolver, solve


# Water data
type WaterDataSets
    junctions
    junction_indexes
    connections
    connection_indexes
    pipe_indexes
    #short_pipe_indexes
    pump_indexes
    valve_indexes
    #control_valve_indexes
    #resistor_indexes
    junction_connections
    #parallel_connections
    #new_connections
    #new_connection_indexes
    #new_pipe_indexes
    #new_compressor_indexes
    #all_parallel_connections # all parallel connections, new and old
    #junction_new_connections
end

abstract AbstractWaterModel
abstract AbstractWaterFormulation

type GenericWaterModel{T<:AbstractWaterFormulation} <: AbstractWaterModel
    model::Model
    data::Dict{AbstractString,Any}
    set::WaterDataSets
    setting::Dict{AbstractString,Any}
    solution::Dict{AbstractString,Any}
end


# default generic constructor
function GenericWaterModel{T}(data::Dict{AbstractString,Any}, vars::T; setting = Dict{AbstractString,Any}(), solver = JuMP.UnsetSolver(), kwargs...)
    data, sets = process_raw_data(data)

    wm = GenericWaterModel{T}(
        Model(solver = solver), # model
        data, # data
        sets, # sets
        setting, # setting
        Dict{AbstractString,Any}(), # solution
    )

    return wm
end

# function for augmenting the data sets
function process_raw_data(data::Dict{AbstractString,Any})
    add_default_data(data)
    sets = build_sets(data)

    # TODO, process the data about share paths etc.
    #add_network_structure(data, sets)
    return data, sets
end

# Set the solver
function JuMP.setsolver(wm::GenericWaterModel, solver::MathProgBase.AbstractMathProgSolver)
    setsolver(wm.model, solver)
end

# Do a solve of the problem
function JuMP.solve(wm::GenericWaterModel)
    status, solve_time, solve_bytes_alloc, sec_in_gc = @timed solve(wm.model)

    try
        solve_time = getsolvetime(wm.model)
    catch
        warn("there was an issue with getsolvetime() on the solver, falling back on @timed.  This is not a rigorous timing value.");
    end

    return status, solve_time
end

# do the run on the abstract model
function run_generic_model(file, model_constructor, solver, post_method; solution_builder = get_solution, kwargs...)
    data = WaterModels.parse_file(file)
    wm = model_constructor(data; solver = solver, kwargs...)
    post_method(wm)
    status, solve_time = solve(wm)
    return build_solution(wm, status, solve_time; solution_builder = solution_builder)
end

# do the run on an already dictionarized model
function run_generic_model(data::Dict{AbstractString,Any}, model_constructor, solver, post_method; solution_builder = get_solution, kwargs...)
    wm = model_constructor(data; solver = solver, kwargs...)
    post_method(wm)
    status, solve_time = solve(wm)
    return build_solution(wm, status, solve_time; solution_builder = solution_builder)
end

# build all the sets that we need for making things easier
function build_sets(data :: Dict{AbstractString,Any})
    junction_lookup = Dict( Int(junction["index"]) => junction for junction in data["junction"] )
    connection_lookup = Dict( Int(connection["index"]) => connection for connection in data["connection"] )
    #new_connection_lookup = Dict( Int(connection["index"]) => connection for connection in data["new_connection"] )

    # filter turned off stuff
    #connection_lookup = filter((i, connection) -> connection["status"] == 1 && connection["f_junction"] in keys(junction_lookup) && connection["t_junction"] in keys(junction_lookup), connection_lookup)
    #new_connection_lookup = filter((i, connection) -> connection["status"] == 1 && connection["f_junction"] in keys(junction_lookup) && connection["t_junction"] in keys(junction_lookup), new_connection_lookup)

    junction_idxs = collect(keys(junction_lookup))
    connection_idxs = collect(keys(connection_lookup))
    #new_connection_idxs = collect(keys(new_connection_lookup))

    pipe_idxs =  collect(keys(filter((i, connection) -> connection["type"] == "pipe", connection_lookup)))
    #short_pipe_idxs = collect(keys(filter((i, connection) -> connection["type"] == "short_pipe", connection_lookup)))
    pump_idxs = collect(keys(filter((i, connection) -> connection["type"] == "pump", connection_lookup)))
    valve_idxs = collect(keys(filter((i, connection) -> connection["type"] == "valve", connection_lookup)))
    #=
    control_valve_idxs = collect(keys(filter((i, connection) -> connection["type"] == "control_valve", connection_lookup)))

    resistor_idxs = collect(keys(filter((i, connection) -> connection["type"] == "resistor", connection_lookup)))

    new_pipe_idxs =  collect(keys(filter((i, connection) -> connection["type"] == "pipe", new_connection_lookup)))
    new_compressor_idxs = collect(keys(filter((i, connection) -> connection["type"] == "new_compressor", connection_lookup)))
    =#
    # parallel_connections = Dict()
    # all_parallel_connections = Dict()

    for connection in [data["connection"]; data["new_connection"]]
        i = connection["f_junction"]
        j = connection["t_junction"]
        # parallel_connections[(min(i,j), max(i,j))] = []
        # all_parallel_connections[(min(i,j), max(i,j))] = []
    end

    junction_connections = Dict(i => [] for (i,junction) in junction_lookup)
    #junction_new_connections = Dict(i => [] for (i,junction) in junction_lookup)

    for connection in data["connection"]
        i = connection["f_junction"]
        j = connection["t_junction"]
        idx = connection["index"]


        push!(junction_connections[i], idx)
        push!(junction_connections[j], idx)

        # push!(parallel_connections[(min(i,j), max(i,j))], idx)
        # push!(all_parallel_connections[(min(i,j), max(i,j))], idx)
    end
   #=
    for connection in data["new_connection"]
        i = connection["f_junction"]
        j = connection["t_junction"]
        idx = connection["index"]

        push!(junction_new_connections[i], idx)
        push!(junction_new_connections[j], idx)

        push!(all_parallel_connections[(min(i,j), max(i,j))], idx)
    end
    =#

    #return WaterDataSets(junction_lookup, junction_idxs, connection_lookup, connection_idxs, pipe_idxs, short_pipe_idxs, compressor_idxs, valve_idxs, control_valve_idxs, resistor_idxs, junction_connections,parallel_connections,new_connection_lookup,new_connection_idxs,new_pipe_idxs,new_compressor_idxs,all_parallel_connections,junction_new_connections)

    #return WaterDataSets(junction_lookup, junction_idxs, connection_lookup, connection_idxs, pipe_idxs, pump_idxs, valve_idxs, junction_connections,parallel_connections,all_parallel_connections)

    return WaterDataSets(junction_lookup, junction_idxs, connection_lookup, connection_idxs, pipe_idxs, pump_idxs, valve_idxs, junction_connections)

end

function add_default_data(data :: Dict{AbstractString,Any})
    if !haskey(data, "new_connection")
        data["new_connection"] = []
    end
 #=
    for connection in [data["connection"]; data["new_connection"]]
        if !haskey(connection,"status")
            connection["status"] = 1
        end
    end


    for connection in data["new_connection"]
        if !haskey(connection,"construction_cost")
            connection["construction_cost"] = 0
        end
    end    =#
end

# Add some necessary data structures for constructing various constraints and variables
function add_network_structure(data :: Dict{AbstractString,Any}, set :: WaterDataSets)
#=
   max_flow = 0

    for junction in data["junction"]
        if junction["qgmax"] > 0
          max_flow = max_flow + junction["qgmax"]
        end
        if junction["qgfirm"] > 0
          max_flow = max_flow + junction["qgfirm"]
        end
        junction["degree"] = 0
        junction["degree_all"] = 0
    end

    for (i,j) in keys(set.parallel_connections)
        if length(set.parallel_connections) > 0
            set.junctions[i]["degree"] = set.junctions[i]["degree"] + 1
            set.junctions[j]["degree"] = set.junctions[j]["degree"] + 1
        end
    end

    for (i,j) in keys(set.all_parallel_connections)
        if length(set.parallel_connections) > 0
            set.junctions[i]["degree_all"] = set.junctions[i]["degree_all"] + 1
            set.junctions[j]["degree_all"] = set.junctions[j]["degree_all"] + 1
        end
    end


    data["max_flow"] = max_flow

    for connection in [data["connection"]; data["new_connection"]]
        i_idx = connection["f_junction"]
        j_idx = connection["t_junction"]

        i = set.junctions[i_idx]
        j = set.junctions[j_idx]

        pd_max = i["pmax"]^2 - j["pmin"]^2
        pd_min = i["pmin"]^2 - j["pmax"]^2

        connection["pd_max"] =  pd_max
        connection["pd_min"] =  pd_min
     end
  =#

end
