export run_owf

function run_owf(network, model_constructor, optimizer; relaxed::Bool=false, kwargs...)
    return run_generic_model(network, model_constructor, optimizer, post_owf, relaxed=relaxed; kwargs...)
end

function post_owf(wm::GenericWaterModel{T}, n::Int=wm.cnw; kwargs...) where T <: AbstractWaterFormulation
    if T <: Union{AbstractMICPForm, AbstractNCNLPForm}
        function_f_alpha(wm, n, convex=false)
    elseif T <: AbstractCNLPForm
        function_if_alpha(wm, n, convex=true)
    end

    variable_head(wm, n)
    variable_flow(wm, n)

    for a in collect(ids(wm, n, :links))
        constraint_potential_loss(wm, a, n)
        constraint_link_flow(wm, a, n)
    end

    for (i, junction) in ref(wm, n, :junctions)
        constraint_flow_conservation(wm, i, n)

        if junction["demand"] > 0.0
            constraint_sink_flow(wm, i, n)
        end
    end

    for i in collect(ids(wm, n, :reservoirs))
        constraint_source_flow(wm, i, n)
    end

    objective_wf(wm, n)
end

function run_mn_owf(file, model_constructor, optimizer; kwargs...)
    return run_generic_model(file, model_constructor, optimizer, post_mn_owf; multinetwork=true, kwargs...)
end

function post_mn_owf(wm::GenericWaterModel{T}; kwargs...) where T <: AbstractWaterFormulation
    for (n, network) in nws(wm)
        if T <: Union{AbstractMICPForm, AbstractNCNLPForm}
            function_f_alpha(wm, n, convex=false)
        elseif T <: AbstractCNLPForm
            function_if_alpha(wm, n, convex=true)
        end

        variable_head(wm, n)
        variable_flow(wm, n)

        for a in ids(wm, n, :links)
            constraint_potential_loss(wm, a, n)
            constraint_link_flow(wm, a, n)
        end

        for (i, junction) in wm.ref[:nw][n][:junctions]
            constraint_flow_conservation(wm, i, n)

            if junction["demand"] > 0.0
                constraint_sink_flow(wm, i, n)
            end
        end

        for i in collect(ids(wm, n, :reservoirs))
            constraint_source_flow(wm, i, n)
        end
    end

    objective_owf(wm)
end