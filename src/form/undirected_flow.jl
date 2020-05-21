# Constraints and variables common to all formulations with undirected flows.
# In these formulations, the variable q correspond to flow between i and j.
# When q is nonnegative, flow is assumed to travel from i to j. When q is
# negative, flow is assumed to travel from j to i.

"Create common flow variables for undirected flow formulations."
function variable_flow_common(wm::AbstractUndirectedFlowModel; nw::Int=wm.cnw, bounded::Bool=true, report::Bool=true)
    # Initialize the variables. (The default start value of 1.0e-6 is crucial.)
    q = var(wm, nw)[:q] = JuMP.@variable(wm.model,
        [a in ids(wm, nw, :link_fixed)], base_name="$(nw)_q",
        start=comp_start_value(ref(wm, nw, :link_fixed, a), "q_start", 1.0e-6))

    if bounded # If the variables are bounded, apply the bounds.
        q_lb, q_ub = calc_flow_bounds(wm, nw)

        for (a, link) in ref(wm, nw, :link_fixed)
            JuMP.set_lower_bound(q[a], minimum(q_lb[a]))
            JuMP.set_upper_bound(q[a], maximum(q_ub[a]))
        end
    end

    # Initialize the solution reporting data structures.
    report && sol_component_value(wm, nw, :link, :q, ids(wm, nw, :link_fixed), q)
end

"Create common network design flow variables for undirected flow formulations."
function variable_flow_des_common(wm::AbstractUndirectedFlowModel; nw::Int=wm.cnw, bounded::Bool=true, report::Bool=true)
    # Create dictionary for undirected design flow variables (i.e., q_des).
    q_des = var(wm, nw)[:q_des] = Dict{Int,Array{JuMP.VariableRef}}()

    # Initialize the variables. (The default start value of 1.0e-6 is crucial.)
    for a in ids(wm, nw, :link_des)
        var(wm, nw, :q_des)[a] = JuMP.@variable(wm.model,
            [r in 1:length(ref(wm, nw, :resistance, a))], base_name="$(nw)_q_des",
            start=comp_start_value(ref(wm, nw, :link_des, a), "q_des_start", r, 1.0e-6))
    end

    if bounded # If the variables are bounded, apply the bounds.
        q_lb, q_ub = calc_flow_bounds(wm, nw)

        for a in ids(wm, nw, :link_des)
            for r in 1:length(ref(wm, nw, :resistance, a))
                JuMP.set_lower_bound(q_des[a][r], q_lb[a][r])
                JuMP.set_upper_bound(q_des[a][r], q_ub[a][r])
            end
        end
    end

    # Create expressions capturing the relationships among q, and q_des.
    q = var(wm, nw)[:q] = JuMP.@expression(
        wm.model, [a in ids(wm, nw, :link_des)], sum(var(wm, nw, :q_des, a)))

    # Initialize the solution reporting data structures.
    report && sol_component_value(wm, nw, :link, :q, ids(wm, nw, :link_des), q)

    # Create resistance binary variables.
    variable_resistance(wm, nw=nw)
end

"Constrain flow variables, based on design selections, in undirected flow formulations."
function constraint_resistance_selection_des(wm::AbstractUndirectedFlowModel, n::Int, a::Int, pipe_resistances)
    c = JuMP.@constraint(wm.model, sum(var(wm, n, :x_res, a)) == 1.0)
    append!(con(wm, n, :head_loss)[a], [c])

    for r in 1:length(pipe_resistances)
        q_des = var(wm, n, :q_des, a)[r]
        x_res = var(wm, n, :x_res, a)[r]

        q_des_lb = JuMP.lower_bound(q_des)
        c_lb = JuMP.@constraint(wm.model, q_des >= q_des_lb * x_res)

        q_des_ub = JuMP.upper_bound(q_des)
        c_ub = JuMP.@constraint(wm.model, q_des <= q_des_ub * x_res)

        append!(con(wm, n, :head_loss)[a], [c_lb, c_ub])
    end
end

function constraint_check_valve_common(wm::AbstractUndirectedFlowModel, n::Int, a::Int, node_fr::Int, node_to::Int, head_fr, head_to)
    # Get flow and check valve status variables.
    q, z = var(wm, n, :q, a), var(wm, n, :z_check_valve, a)

    # If the check valve is open, flow must be appreciably nonnegative.
    c_1 = JuMP.@constraint(wm.model, q <= JuMP.upper_bound(q) * z)
    c_2 = JuMP.@constraint(wm.model, q >= 6.31465679e-6 * z)

    # Get head variables for from and to nodes.
    h_i, h_j = [var(wm, n, :h, node_fr), var(wm, n, :h, node_to)]

    # When the check valve is open, negative head loss is not possible.
    dh_lb = JuMP.lower_bound(h_i) - JuMP.upper_bound(h_j)
    c_3 = JuMP.@constraint(wm.model, h_i - h_j >= (1.0 - z) * dh_lb)

    # When the check valve is closed, positive head loss is not possible.
    dh_ub = JuMP.upper_bound(h_i) - JuMP.lower_bound(h_j)
    c_4 = JuMP.@constraint(wm.model, h_i - h_j <= z * dh_ub)

    # Append the constraint array.
    append!(con(wm, n, :check_valve, a), [c_1, c_2, c_3, c_4])
end

function constraint_sv_common(wm::AbstractUndirectedFlowModel, n::Int, a::Int, node_fr::Int, node_to::Int, head_fr, head_to)
    # Get flow and shutoff valve status variables.
    q, z = var(wm, n, :q, a), var(wm, n, :z_shutoff_valve, a)
    yp, yn = var(wm, n, :yp, a), var(wm, n, :yn, a)

    # If the shutoff valve is open, flow must be appreciably nonnegative.
    c_1 = JuMP.@constraint(wm.model, yp + yn == z) # Directions will be zero when off.
    c_2 = JuMP.@constraint(wm.model, q <= JuMP.upper_bound(q) * yp - 6.31465679e-6 * yn)
    c_3 = JuMP.@constraint(wm.model, q >= JuMP.lower_bound(q) * yn + 6.31465679e-6 * yp)

    # Append the constraint array.
    append!(con(wm, n, :sv, a), [c_1, c_2, c_3])
end

function constraint_prv_common(wm::AbstractUndirectedFlowModel, n::Int, a::Int, node_fr::Int, node_to::Int, head_fr, head_to, h_prv::Float64)
    # Get flow and pressure reducing valve status variables.
    q, z = var(wm, n, :q, a), var(wm, n, :z_pressure_reducing_valve, a)

    # If the pressure reducing valve is open, flow must be appreciably nonnegative.
    c_1 = JuMP.@constraint(wm.model, q <= JuMP.upper_bound(q) * z)
    c_2 = JuMP.@constraint(wm.model, q >= 6.31465679e-6 * z)

    # Get head variables for from and to nodes.
    h_i, h_j = var(wm, n, :h, node_fr), var(wm, n, :h, node_to)

    # When the pressure reducing valve is open, the head at node j is predefined.
    h_lb, h_ub = JuMP.lower_bound(h_j), JuMP.upper_bound(h_j)
    c_3 = JuMP.@constraint(wm.model, h_j >= (1.0 - z) * h_lb + z * h_prv)
    c_4 = JuMP.@constraint(wm.model, h_j <= (1.0 - z) * h_ub + z * h_prv)

    # When the pressure reducing valve is open, the head loss is nonnegative.
    dh_lb = JuMP.lower_bound(h_i) - JuMP.lower_bound(h_j)
    c_5 = JuMP.@constraint(wm.model, h_i - h_j >= dh_lb * (1.0 - z))

    # Append the constraint array.
    append!(con(wm, n, :prv, a), [c_1, c_2, c_3, c_4, c_5])
end

function constraint_pump_common(wm::AbstractUndirectedFlowModel, n::Int, a::Int, node_fr::Int, node_to::Int, head_fr, head_to, pc::Array{Float64})
    # Gather common variables.
    z = var(wm, n, :z_pump, a)
    q, g = var(wm, n, :q, a), var(wm, n, :g, a)
    h_i, h_j = var(wm, n, :h, node_fr), var(wm, n, :h, node_to)

    # If the pump is off, the flow along the pump must be zero.
    c_1 = JuMP.@constraint(wm.model, q <= JuMP.upper_bound(q) * z)
    c_2 = JuMP.@constraint(wm.model, q >= 6.31465679e-6 * z)

    # If the pump is off, decouple the head difference relationship.
    dhn_lb = JuMP.lower_bound(h_j) - JuMP.upper_bound(h_i)
    c_3 = JuMP.@constraint(wm.model, h_j - h_i - g >= dhn_lb * (1.0 - z))
    dhn_ub = JuMP.upper_bound(h_j) - JuMP.lower_bound(h_i)
    c_4 = JuMP.@constraint(wm.model, h_j - h_i - g <= dhn_ub * (1.0 - z))

    # Append the constraint array.
    append!(con(wm, n, :pump, a), [c_1, c_2, c_3, c_4])
end

function constraint_pipe_common(wm::AbstractUndirectedFlowModel, n::Int, a::Int, node_fr::Int, node_to::Int, alpha::Float64, L::Float64, r::Float64)
    # For undirected formulations, there are no constraints, here.
end

function constraint_sink_flow(wm::AbstractWaterModel, n::Int, i::Int, a_fr::Array{Tuple{Int,Int,Int}}, a_to::Array{Tuple{Int,Int,Int}})
    # For undirected formulations, there are no constraints, here.
end

function constraint_source_flow(wm::AbstractWaterModel, n::Int, i::Int, a_fr::Array{Tuple{Int,Int,Int}}, a_to::Array{Tuple{Int,Int,Int}})
    # For undirected formulations, there are no constraints, here.
end

function constraint_flow_direction_selection_des(wm::AbstractUndirectedFlowModel, n::Int, a::Int, pipe_resistances) end
function constraint_head_loss_ub_cv(wm::AbstractUndirectedFlowModel, n::Int, a::Int, alpha::Float64, L::Float64, r::Float64) end
function constraint_shutoff_valve_head_loss_ub(wm::AbstractUndirectedFlowModel, n::Int, a::Int, alpha::Float64, L::Float64, r::Float64) end
function constraint_pipe_head_loss_ub_des(wm::AbstractUndirectedFlowModel, n::Int, a::Int, alpha, len, pipe_resistances) end
function constraint_pipe_head_loss_ub(wm::AbstractUndirectedFlowModel, n::Int, a::Int, alpha, len, r_max) end
function constraint_energy_conservation(wm::AbstractUndirectedFlowModel, n::Int, r, L, alpha) end
