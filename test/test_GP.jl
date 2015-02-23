using gaussianprocesses

d, n = 10, 20

x = 2π * rand(d, n)
y = Float64[sum(sin(x[:,i])) for i in 1:n]/d
gp = GP(x, y, meanZero, rbf)

# Function verifies that predictive mean at input observations
# are the same as the output observations
function test_pred_matches_obs(gp::GP)
    y_pred, sig = predict(gp, x)
    @test_approx_eq_eps maximum(abs(gp.y - y_pred)) 0.0 1e-4
end

test_pred_matches_obs(gp)
