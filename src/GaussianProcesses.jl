module GaussianProcesses
using Optim, PDMats, Distances
using Compat
import Compat: view, cholfact!

import Base: +, *
import Base: rand, rand!, mean, cov, push!

# Functions that should be available to package
# users should be explicitly exported here

export GP, predict, SumKernel, ProdKernel, Masked, FixedKern, fix, Noise, Kernel, SE, SEIso, SEArd, Periodic, Poly, RQ, RQIso, RQArd, Lin, LinIso, LinArd, Mat, Mat12Iso, Mat12Ard, Mat32Iso, Mat32Ard, Mat52Iso, Mat52Ard, MeanZero, MeanConst, MeanLin, MeanPoly, MeanQuad, SumMean, ProdMean, optimize!, mcmc

typealias MatF64 AbstractMatrix{Float64}
typealias VecF64 AbstractVector{Float64}

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
    init = Symbol(string(pkg,"_init"))
    quote
        $(esc(init))() = Base.include($path)
        isdefined(Main,$(QuoteNode(pkg))) && $(esc(init))()
    end
end

@glue Gadfly
@glue PyPlot
# This does not require @glue because it uses the interface defined in
# ScikitLearnBase, which is a skeleton package.
include("glue/ScikitLearn.jl")

end # module
