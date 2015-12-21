module GaussianProcesses
using Optim, PDMats, Distances, ArrayViews, Mamba
VERSION < v"0.4-" && using Docile

import Base: +, *
import Mamba: mcmc

# Functions that should be available to package
# users should be explicitly exported here

export GP, predict, SumKernel, ProdKernel, Noise, Kernel, SE, SEIso, SEArd, Periodic, Poly, RQ, RQIso, RQArd, Lin, LinIso, LinArd, Mat, Mat12Iso, Mat12Ard, Mat32Iso, Mat32Ard, Mat52Iso, Mat52Ard, MeanZero, MeanConst, MeanLin, MeanPoly, MeanPrior, SumMean, ProdMean, optimize!, mcmc, predictGrad, predictGrad2

# all package code should be included here
include("means/meanFunctions.jl")
include("kernels/kernels.jl")
include("utils.jl")
include("GP.jl")
include("optimize.jl")
include("mcmc.jl")

# This approach to loading supported plotting packages is taken from the "KernelDensity" package
macro glue(pkg)
    path = joinpath(dirname(@__FILE__),"glue",string(pkg,".jl"))
    init = symbol(string(pkg,"_init"))
    quote
        $(esc(init))() = Base.include($path)
        isdefined(Main,$(QuoteNode(pkg))) && $(esc(init))()
    end
end

@glue Gadfly
@glue Winston

end # module
