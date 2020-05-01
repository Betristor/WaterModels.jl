@testset "src/core/base.jl" begin
    wm = instantiate_model("../test/data/epanet/shamir.inp", CNLPWaterModel, WaterModels.build_wf)

    @testset "silence" begin
        # This should silence everything except error messages.
        WaterModels.silence()

        wm_logger = Memento.getlogger(InfrastructureModels)
        @test Memento.getlevel(wm_logger) == "error"
        Memento.warn(wm_logger, "Silenced message should not be displayed.")

        wm_logger = Memento.getlogger(WaterModels)
        @test Memento.getlevel(wm_logger) == "error"
        Memento.warn(wm_logger, "Silenced message should not be displayed.")
    end
end
