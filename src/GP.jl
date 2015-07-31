import Base.show

# Main GaussianProcess type

@doc """
# Description
Fits a Gaussian process to a set of training points. The Gaussian process is defined in terms of its mean and covaiance (kernel) functions, which are user defined. As a default it is assumed that the observations are noise free.
# Arguments:
* `x::Matrix{Float64}`: Training inputs
* `y::Vector{Float64}`: Observations
* `m::Mean`           : Mean function
* `k::kernel`         : Covariance function
* `logNoise::Float64` : Log of the observation noise. The default is -1e8, which is equivalent to assuming no observation noise.
# Returns:
* `gp::GP`            : A Gaussian process fitted to the training data
""" ->
type GP
    x::Matrix{Float64}      # Input observations  - each column is an observation
    y::Vector{Float64}      # Output observations
    dim::Int                # Dimension of inputs
    nobsv::Int              # Number of observations
    logNoise::Float64       # log variance of observation noise
    m:: Mean                # Mean object
    k::Kernel               # Kernel object
    # Auxiliary data
    cK::AbstractPDMat       # (k + obsNoise)
    alpha::Vector{Float64}  # (k + obsNoise)⁻¹y
    mLL::Float64            # Marginal log-likelihood
    dmLL::Vector{Float64}   # Gradient marginal log-likelihood
    H::Matrix{Float64}      # Matrix to stack mean functions h(x) = (1,x,x²,..)
    A::Matrix{Float64}      
    Ah::Matrix{Float64}     
    
    function GP(x::Matrix{Float64}, y::Vector{Float64}, m::Mean, k::Kernel, logNoise::Float64=-1e8)
        dim, nobsv = size(x)
        length(y) == nobsv || throw(ArgumentError("Input and output observations must have consistent dimensions."))
        gp = new(x, y, dim, nobsv, logNoise, m, k)
        if isa(gp.m,MeanPrior)
            update_mll_prior!(gp)
        else
            update_mll!(gp)
        end            
        return gp
   end
end

# Creates GP object for 1D case
GP(x::Vector{Float64}, y::Vector{Float64}, meanf::Mean, kernel::Kernel, logNoise::Float64=-1e8) = GP(x', y, meanf, kernel, logNoise)

# Update auxiliarly data in GP object after changes have been made
function update_mll!(gp::GP)
    m = meanf(gp.m,gp.x)
    gp.cK = PDMat(crossKern(gp.x,gp.k) + exp(gp.logNoise)*eye(gp.nobsv))
    gp.alpha = gp.cK \ (gp.y - m)
    gp.mLL = -dot((gp.y-m),gp.alpha)/2.0 - logdet(gp.cK)/2.0 - gp.nobsv*log(2π)/2.0 #Marginal log-likelihood
end

# Update marginal log-likelihood where we have integrated out the mean function parameters with a non-informative Gaussian prior
function update_mll_prior!(gp::GP)
    gp.H = meanf(gp.m,gp.x)
    gp.cK = PDMat(crossKern(gp.x,gp.k) + exp(gp.logNoise)*eye(gp.nobsv))
    gp.alpha = gp.cK \gp.y
    Hck = whiten(gp.cK,gp.H')
    gp.A = Hck'Hck
    gp.Ah = whiten(PDMat(gp.A),gp.H)
    gp.mLL = -dot(gp.y,gp.alpha)/2.0 +dot(gp.alpha'*gp.Ah'gp.Ah,gp.alpha)/2.0 -logdet(gp.cK)/2.0 -logdet(gp.A)/2.0 - (gp.nobsv-rank(gp.H'))*log(2π)/2.0 #Marginal log-likelihood
end

# Update gradient of marginal log likelihood
function update_mll_and_dmll!(gp::GP; noise::Bool=true, mean::Bool=true, kern::Bool=true)
    
    update_mll!(gp::GP)
    
    gp.dmLL = Array(Float64, noise + mean*num_params(gp.m) + kern*num_params(gp.k))

    # Calculate Gradient with respect to hyperparameters

    #Derivative wrt the observation noise
    if noise
        gp.dmLL[1] = exp(2*gp.logNoise)*trace((gp.alpha*gp.alpha' - gp.cK \ eye(gp.nobsv)))
    end

    #Derivative wrt to mean hyperparameters, need to loop over as same with kernel hyperparameters
    if mean
        Mgrads = grad_stack(gp.x, gp.m)
        for i in 1:num_params(gp.m)
            gp.dmLL[i+noise] = -dot(Mgrads[:,i],gp.alpha)
        end
    end

    # Derivative of marginal log-likelihood with respect to kernel hyperparameters
    if kern
        Kgrads = grad_stack(gp.x, gp.k)   # [dK/dθᵢ]
        for i in 1:num_params(gp.k)
            gp.dmLL[i+mean*num_params(gp.m)+noise] = trace((gp.alpha*gp.alpha' - gp.cK \ eye(gp.nobsv))*Kgrads[:,:,i])/2
        end
    end
end

# Update gradient of the marginal log likelihood for the case where we integrate out the mean function parameters
function update_mll_and_dmll_prior!(gp::GP; noise::Bool=true, kern::Bool=true)
    khah = gp.cK\gp.Ah'gp.Ah    
    update_mll_prior!(gp::GP)
    
    gp.dmLL = Array(Float64, noise + kern*num_params(gp.k))

    # Calculate Gradient with respect to hyperparameters

    #Derivative wrt the observation noise
    if noise
        gp.dmLL[1] = exp(2*gp.logNoise)*(trace((gp.alpha*gp.alpha'*(eye(gp.nobsv) -2*khah') - gp.cK \ eye(gp.nobsv) + khah*gp.alpha*gp.alpha'*khah'))/2.0 -trace(-gp.A\(gp.cK\gp.H')'*(gp.cK\gp.H'))/2.0)
    end

    # Derivative of marginal log-likelihood with respect to kernel hyperparameters
    if kern
        Kgrads = grad_stack(gp.x, gp.k)   # [dK/dθᵢ]
        for i in 1:num_params(gp.k)
            gp.dmLL[i+noise] = trace((gp.alpha*gp.alpha'*(eye(gp.nobsv) -2*khah') - gp.cK \ eye(gp.nobsv) + khah*gp.alpha*gp.alpha'*khah')*Kgrads[:,:,i])/2.0-trace(-gp.A\(gp.cK\gp.H')'*Kgrads[:,:,i]*(gp.cK\gp.H'))/2.0
        end
    end
end


@doc """
# Description
Calculates the posterior mean and variance of Gaussian Process at specified points
# Arguments:
* `gp::GP`: Gaussian Process object
* `x::Matrix{Float64}`:  matrix of points for which one would would like to predict the value of the process.
                       (each column of the matrix is a point)
# Returns:
* `(mu, Sigma)::(Vector{Float64}, Vector{Float64})`: respectively the posterior mean  and variances of the posterior
                                                    process at the specified points
""" ->
function predict(gp::GP, x::Matrix{Float64}; full_cov::Bool=false)
    size(x,1) == gp.dim || throw(ArgumentError("Gaussian Process object and input observations do not have consistent dimensions"))
    if full_cov
        return _predict(gp, x)
    else
        ## calculate prediction for each point independently
            mu = Array(Float64, size(x,2))
            Sigma = similar(mu)
        if isa(gp.m,MeanPrior)
            for k in 1:size(x,2)
                out = _predictPrior(gp, x[:,k:k])
                mu[k] = out[1][1]
                Sigma[k] = out[2][1]
            end
        else
            for k in 1:size(x,2)
                out = _predict(gp, x[:,k:k])
                mu[k] = out[1][1]
                Sigma[k] = out[2][1]
            end
        end            
        return mu, Sigma
    end
end

# 1D Case for prediction
predict(gp::GP, x::Vector{Float64};full_cov::Bool=false) = predict(gp, x'; full_cov=full_cov)

## compute predictions assuming we integrate out the mean function hyperparameters with a non-informative Gaussian prior
function _predictPrior(gp::GP, x::Array{Float64})
    cK  = crossKern(x,gp.x,gp.k)
    Lck = whiten(gp.cK, cK')
    H   = meanf(gp.m,x)
    Hck = whiten(gp.cK,gp.H')
    A   = PDMat(Hck'Hck)
    beta = A\gp.H*gp.alpha
    R    = H - whiten(gp.cK,gp.H')'Lck
    mu = cK*gp.alpha + R'*beta                          # Predictive mean
    LaR = whiten(A, R)
    Sigma = crossKern(x,gp.k) - Lck'Lck + LaR'LaR  # Predictive covariance
    Sigma = max(Sigma,0)
    return (mu, Sigma)
end

## compute predictions
function _predict(gp::GP, x::Array{Float64})
    cK = crossKern(x,gp.x,gp.k)
    Lck = whiten(gp.cK, cK')
    mu = meanf(gp.m,x) + cK*gp.alpha    # Predictive mean
    Sigma = crossKern(x,gp.k) - Lck'Lck # Predictive covariance
    Sigma = max(Sigma,0)
    return (mu, Sigma)
end


function get_params(gp::GP; noise::Bool=true, mean::Bool=true, kern::Bool=true)
    params = Float64[]
    if noise; push!(params, gp.logNoise); end
    if mean;  append!(params, get_params(gp.m)); end
    if kern; append!(params, get_params(gp.k)); end
    return params
end

function set_params!(gp::GP, hyp::Vector{Float64}; noise::Bool=true, mean::Bool=true, kern::Bool=true)
    # println("mean=$(mean)")
    if noise; gp.logNoise = hyp[1]; end
    if mean; set_params!(gp.m, hyp[1+noise:noise+num_params(gp.m)]); end
    if kern; set_params!(gp.k, hyp[end-num_params(gp.k)+1:end]); end
end

function show(io::IO, gp::GP)
    println(io, "GP object:")
    println(io, "  Dim = $(gp.dim)")
    println(io, "  Number of observations = $(gp.nobsv)")
    println(io, "  Mean function:")
    show(io, gp.m, 2)
    println(io, "  Kernel:")
    show(io, gp.k, 2)
    println(io, "  Input observations = ")
    show(io, gp.x)
    print(io,"\n  Output observations = ")
    show(io, gp.y)
    print(io,"\n  Variance of observation noise = $(exp(gp.logNoise))")
    print(io,"\n  Marginal Log-Likelihood = ")
    show(io, round(gp.mLL,3))
end
