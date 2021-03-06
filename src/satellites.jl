"""
    gridRectangular(xdim, ydim)

Create coordinates of all neurons on a rectangular SOM.

The return-value is an array of size (Number-of-neurons, 2) with
x- and y- coordinates of the neurons in the first and second
column respectively.
The distance between neighbours is 1.0.
The point of origin is bottom-left.
The first neuron sits at (0,0).

# Arguments
- `xdim`: number of neurons in x-direction
- `ydim`: number of neurons in y-direction
"""
function gridRectangular(xdim, ydim)

    grid = zeros(Float64, (xdim*ydim, 2))
    for ix in 1:xdim
        for iy in 1:ydim

            grid[ix+(iy-1)*xdim, 1] = ix-1
            grid[ix+(iy-1)*xdim, 2] = iy-1
        end
    end
    return grid
end


"""
    gaussianKernel(x, r::Float64)

Return Gaussian(x) for μ=0.0 and σ = r/3.
(a value of σ = r/3 makes the training results comparable between different kernels
for same values of r).

# Arguments

"""
function gaussianKernel(x, r::Float64)

    return Distributions.pdf.(Distributions.Normal(0.0,r/3), x)
end


"""
    distMatrix(grid::Array, toroidal::Bool)::Array{Float64, 2}

Return the distance matrix for a non-toroidal or toroidal SOM.

# Arguments
- `grid`: coordinates of all neurons as generated by one of the `grid-`functions
with x-coordinates in 1st column and y-coordinates in 2nd column.
- `toroidal`: true for a toroidal SOM.
"""
function distMatrix(grid::Array, toroidal::Bool)::Array{Float64, 2}

    X = 1
    Y = 2
    xdim = maximum(grid[:,X]) - minimum(grid[:,X]) + 1.0
    ydim = maximum(grid[:,Y]) - minimum(grid[:,Y]) + 1.0

    numNeurons = size(grid,1)

    dm = zeros(Float64, (numNeurons,numNeurons))
    for i in 1:numNeurons
        for j in 1:numNeurons
            Δx = abs(grid[i,X] - grid[j,X])
            Δy = abs(grid[i,Y] - grid[j,Y])

            if toroidal
                Δx = min(Δx, xdim-Δx)
                Δy = min(Δy, ydim-Δy)
            end

            dm[i,j] = √(Δx^2 + Δy^2)
        end
    end
    # show(STDOUT, "text/plain",  grid)
    # show(STDOUT, "text/plain",  dm)
    return dm
end


"""
    classFrequencies(som::Som, data, classes)

Return a DataFrame with class frequencies for all neurons.

# Arguments:
- `som`: a trained SOM
- `data`: data with row-wise samples and class information in each row
- `classes`: Name of column with class information.

Data must have the same number of dimensions as the training dataset.
The column with class labels is given as `classes` (name or index).
Returned DataFrame has the columns:
* X-, Y-indices and index: of winner neuron for every row in data
* population: number of samples mapped to the neuron
* frequencies: one column for each class label.
"""
function classFrequencies(som::Som, data, classes)

    if size(data,2) != size(som.codes,2) + 1
        println("    data: $(size(data,2)-1), codes: $(size(som.codes,2))")
        error(SOM_ERRORS[:ERR_COL_NUM])
    end

    x = deepcopy(data)
    deletecols!(x, classes)
    classes = data[classes]
    vis = visual(som.codes, x)

    df = makeClassFreqs(som, vis, classes)
    return df
end


"""
    visual(codes::Array{Float64,2}, x::Array{Float64,2})

Return the index of the winner neuron for each training pattern
in x (row-wise).

# Arguments
- `codes`: Codebook
- `x`: training Data
"""
function visual(codes::Array{Float64,2}, x::Array{Float64,2})

    vis = zeros(Int, size(x,1))
    for i in 1:size(x,1)

        vis[i] = findBmu(codes, x[i, : ])
    end

    return vis
end


"""
    makePopulation(numCodes, vis)

Return a vector of neuron populations.

# Arguments
- `numCodes`: total number of neurons
- `vis`: index of the winner neuron for each training pattern in x
"""
function makePopulation(numCodes, vis)

    population = zeros(Int, numCodes)
    for i in 1:size(vis,1)
        population[vis[i]] += 1
    end

    return population
end


"""
    makeClassFreqs(som, vis, classes)

Return a DataFrame with class frequencies for all neurons.

# Arguments
- `som`: a trained SOM
- `vis`: index of the winner neuron for each training pattern in x
- `classes`: name of column with class information
"""
function makeClassFreqs(som, vis, classes)

    # count classes and construct DataFrame:
    #
    classLabels = sort(unique(classes))
    classNum = size(classLabels,1)

    cfs = DataFrame(index = 1:som.numCodes)
    cfs[:X] = som.indices[:X]
    cfs[:Y] = som.indices[:Y]

    cfs[:Population] = zeros(Int, som.numCodes)

    for class in classLabels
        cfs[Symbol(class)] = zeros(Float64, som.numCodes)
    end

    # loop vis and count:
    #
    for i in 1:size(vis,1)

        cfs[vis[i], :Population] += 1
        class = Symbol(classes[i])
        cfs[vis[i], class] += 1
    end

    # make frequencies from counts:
    #
    for i in 1:size(cfs,1)

        counts = [cfs[i, col] for col in 5:size(cfs, 2)]
        total = cfs[i,:Population]
        if total == 0
            freqs = counts * 0.0
        else
            freqs = counts ./ total
        end

        for c in 1:classNum
            class = Symbol(classLabels[c])
            cfs[i,class] = freqs[c]
        end
    end

    return cfs
end


"""
    findBmu(codes::Array{Float64,2}, sample::Array{Float64,1})::Int64

Find the best matching unit for a given vector, row_t, in the SOM

Returns: Index of bmu
Best Matching Unit and bmuIdx is the index of this vector in the SOM

# Arguments
- `codes`: 2D-array of codebook vectors. One vector per row
- `sample`: row in dataset / trainingsset

"""
function findBmu(codes::Array{Float64,2}, sample::Array{Float64,1})::Int64

    x = Distances.colwise(Euclidean(), sample, codes')

    return argmin(x)

end


"""
    normTrainData(x::Array{Float64,2}, normParams)

Normalise every column of training data with the params.

# Arguments
- `x`: DataFrame with training Data
- `normParams`: Shift and scale parameters for each attribute column.
"""
function normTrainData(x::Array{Float64,2}, normParams)

    for i in 1:size(x,2)
        x[:,i] = (x[:,i] .- normParams[1,i]) ./ normParams[2,i]
    end

    return x
end


"""
    normTrainData(train::Array{Float64, 2}, norm::Symbol)

Normalise every column of training data.

# Arguments
- `train`: DataFrame with training Data
- `norm`: type of normalisation; one of `minmax, zscore, none`
"""
function normTrainData(train::Array{Float64, 2}, norm::Symbol)

    normParams = zeros(2, size(train,2))

    if  norm == :minmax
        for i in 1:size(train,2)
            normParams[1,i] = minimum(train[:,i])
            normParams[2,i] = maximum(train[:,i]) - minimum(train[:,i])
        end
    elseif norm == :zscore
        for i in 1:size(train,2)
            normParams[1,i] = mean(train[:,i])
            normParams[2,i] = std(train[:,i])
        end
    else
        for i in 1:size(train,2)
            normParams[1,i] = 0.0  # shift
            normParams[2,i] = 1.0  # scale
        end
    end

    # do the scaling:
    if norm == :none
        x = train
    else
        x = normTrainData(train, normParams)
    end

    return x, normParams
end


"""
    convertTrainingData(data)::Array{Float64,2}

Converts the training data to an Array of type Float64.

# Arguments:
- `data`: Data to be converted

"""
function convertTrainingData(data)::Array{Float64,2}

    if typeof(data) == DataFrame
        train = convert(Matrix{Float64}, data)

    elseif typeof(data) != Matrix{Float64}
        try
            train = convert(Matrix{Float64}, data)
        catch ex
            Base.showerror(STDERR, ex, backtrace())
            error("Unable to convert training data to Array{Float64,2}!")
        end
    else
        train = data
    end

    return train
end

prettyPrintArray(arr) = println("$(show(IOContext(STDOUT, limit=true), "text/plain", arr))")


"""
    checkDir()

Checks if the `pwd()` is the `/test` directory, and if not it changes to it.

"""
function checkDir()

    files = readdir()
    if !in("runtests.jl", files)
        cd(dirname(dirname(pathof(GigaSOM))))
    end
end
