# tools for working with WaterModels internal data format

# "Computes the maximum flow of the Water Model"
# function calc_max_flow(data::Dict{String,Any})
#     max_flow = 0
#     for (idx, junction) in data["junction"]
#         if junction["qgmax"] > 0
#           max_flow = max_flow + junction["qgmax"]
#         end
#         if junction["qgfirm"] > 0
#           max_flow = max_flow + junction["qgfirm"]
#         end
#     end
#     return max_flow
# end

"Ensures that status exists as a field in connections"
function add_default_status(data::Dict{String,Any})
    # for entry in [data["connection"]; data["ne_connection"]]
    for entry in [data["connection"]]
        for (idx,connection) in entry
            if !haskey(connection,"status")
                connection["status"] = "open"
            end
        end
    end
end

# "Ensures that construction cost exists as a field for new connections"
# function add_default_construction_cost(data::Dict{String,Any})
#     for (idx, connection) in data["ne_connection"]
#         if !haskey(connection,"construction_cost")
#             connection["construction_cost"] = 0
#         end
#     end
# end

"Add the degree information"
function add_degree(ref::Dict{Symbol,Any})
    for (i,junction) in ref[:junction]
        junction["degree"] = 0
        junction["degree_all"] = 0
    end

    for (i,j) in keys(ref[:parallel_connections])
        if length(ref[:parallel_connections]) > 0
            ref[:junction][i]["degree"] = ref[:junction][i]["degree"] + 1
            ref[:junction][j]["degree"] = ref[:junction][j]["degree"] + 1
        end
    end

    # for (i,j) in keys(ref[:all_parallel_connections])
    #     if length(ref[:parallel_connections]) > 0
    #         ref[:junction][i]["degree_all"] = ref[:junction][i]["degree_all"] + 1
    #         ref[:junction][j]["degree_all"] = ref[:junction][j]["degree_all"] + 1
    #     end
    # end
end

"Add the bounds for minimum and maximum head"
function add_hd_bounds(ref::Dict{Symbol,Any})
    # for entry in [ref[:connection]; ref[:ne_connection]]
    for entry in [ref[:connection]]
        for (idx,connection) in entry
            i_idx = connection["f_junction"]
            j_idx = connection["t_junction"]

            i = ref[:junction][i_idx]
            j = ref[:junction][j_idx]

            hd_max = 10^6
            hd_min = -10^6
            # pd_max = i["pmax"]^2 - j["pmin"]^2
            # pd_min = i["pmin"]^2 - j["pmax"]^2

            connection["hd_max"] =  hd_max
            connection["hd_min"] =  hd_min
        end
    end
end

"Add resistance_pipe"
function add_resistance_pipe(ref::Dict{Symbol,Any})
  for entry in [ref[:pipe]]
    for (idx,pipe) in entry
      pipe["resistance"] = 4.727*pipe["roughness"]^(-1.852)*(pipe["diameter"])^(-4.871)*pipe["length"];
    end
  end
end
