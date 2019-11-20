################################################################################
# model__equations = "y1 = A + B
#                     y2 = A + B + A*B"
#
# the class ModelTerm is shown below for one term in model_equations, such as
# terms: y1:A, y1:B, y2:A, y2:B, y2:A*B
#
################################################################################
mutable struct ModelTerm
    iModel::Int64                  # 1st (1) or 2nd (2) model_equation
    iTrait::AbstractString         # trait 1 ("y1") or trait 2 ("y2") (trait name)
                                   # | trmStr  | nFactors  | factors |
                                   # |---------|-----------|---------|
    trmStr::AbstractString         # | "y1:A"  |     1     | :A      |
    nFactors::Int64                # | "y2:A"  |     1     | :A      |
    factors::Array{Symbol,1}       # | "y1:A*B"|     2     | :A,:B   |

                                   #DATA             |          str               |     val       |
                                   #                :|----------------------------|---------------|
    str::Array{AbstractString,1}   #covariate^2     :|["A x B", "A X B", ...]     | df[:A].*df[:B]|
    val::Array{Float64,1}          #factor^2        :|["A1 x B1", "A2 X B2", ...] | [1.0,1.0,...] |
                                   #factor*covariate:|["A1 x B","A2 X B", ...]    | 1.0.*df[:B]   |

                                   #OUTPUT           | nLevels |     names        |
                                   #                 |---------|------------------|
    nLevels::Int64                 #covariate   :    | 1       | "A"              |
    names::Array{Any,1}            #factor      :    | nLevels | "A1", "A2", ...  |
                                   #animal (ped):    | nAnimals| ids              |
                                   #animal(ped)*age: | nAnimals| "A1*age","A2*age"|
                                   #factor*covariate:| nLevels | "A1*age","A2*age"|

    startPos::Int64                   #start postion for this term in incidence matrix
    X::SparseMatrixCSC{Float64,Int64} #incidence matrix

    random_type::String

    function ModelTerm(trmStr,m,traitname)
        iModel    = m
        trmStr    = strip(trmStr)
        traitname = strip(traitname)
        factorVec = split(trmStr,"*")
        nFactors  = length(factorVec)
        factors   = [Symbol(strip(f)) for f in factorVec]
        trmStr    = traitname*":"*trmStr
        new(iModel,traitname,trmStr,nFactors,factors,[],[],0,[],0,spzeros(0,0),"fixed")
    end
end

################################################################################
#A class for residual covariance matrix for all observations of size (nob*nModel)
#where Ri is modified based on missing pattern (number of Ri= 2^nTrait-1)
#It allows using the same incidence matrix X for all traits in multi-trait analyses
#In JWAS, ONLY used when residual variance is constant
#or missing phenotypes are not imputed at each step of MCMC (no marker effects).
################################################################################
mutable struct ResVar
    R0::Array{Float64,2}
    RiDict::Dict{BitArray{1},Array{Float64,2}}
end

################################################################################
#General (including i.i.d.) random effects
#Assume independence:cov(1:A,1:B)=0 unless A.names == B.names, e.g.pedigree(pedTrmVec)
#single-trait e.g. termarray: [ModelTerm(1:A)]
#multi-trait  e.g. termarray: [ModelTerm(1:A), ModelTerm(2:A)]
################################################################################
mutable struct RandomEffect   #Better to be a dict? key: term_array::Array{AbstractString,1}??
    term_array::Array{AbstractString,1}
    Gi::Array{Float64,2}     #covariance matrix (multi-trait)
    GiOld::Array{Float64,2}  #specific for lambda version of MME (single-trait)
    GiNew::Array{Float64,2}  #specific for lambda version of MME (single-trait)
    df::Float64
    scale #::Array{Float64,2}
    Vinv # 0, identity matrix
    names #[] General IDs and Vinv matrix (order is important now)(modelterm.names)
    randomType::String
end

mutable struct Genotypes
  obsID::Array{AbstractString,1}  #row ID for (imputed) genotyped and phenotyped inds (finally)
  markerID
  nObs::Int64                     #length of obsID
  nMarkers::Int64
  alleleFreq::Array{Float64,2}
  sum2pq::Float64
  centered::Bool
  genotypes::Array{Float64,2}
  genetic_variance  #genetic variance
  G                 #marker effect variance; ST->Float64;MT->Array{Float64,2}
  scale             #scale parameter for marker effect variance (G)
  Genotypes(a1,a2,a3,a4,a5,a6,a7,a8)=new(a1,a2,a3,a4,a5,a6,a7,a8,false,false,false)
end

mutable struct DF
    residual::Float64
    polygenic::Float64  #df+size(mme.pedTrmVec,1)
    marker::Float64
    random::Float64
end

mutable struct MCMCinfo
    chain_length
    starting_value
    burnin
    output_samples_file
    output_samples_frequency
    printout_model_info
    printout_frequency
    methods
    Pi
    estimatePi
    estimateScale
    single_step_analysis
    missing_phenotypes
    constraint
    estimate_variance
    update_priors_frequency
    outputEBV
    output_heritability
    categorical_trait
    seed
end
################################################################################
#the class MME is shown below with members for models, mixed model equations...
#
#Single-trait analysis: lambda version of MME
#Multi-trait analysis : formal version of MME
#
#Details:
#Scale parameters:
#Scale parameters for variance components are computed when variances are added
#i.e., build_model() for residual variance; set_random() for non-marker random
#effects except scale parameter for marker effect variance, which is computed in
#the function set_marker_hyperparameters_variances_and_pi() where marker effect
#variance is computed based genetic varaince and pi.
#
################################################################################
mutable struct MME
    nModels::Int64                                #number of model equations
    modelVec::Array{AbstractString,1}             #["y1 = A + B","y2 = A + B + A*B"]
    modelTerms::Array{ModelTerm,1}                #ModelTerms for "1:intercept","1:A","2:intercept","2:A","2:A*B"...;
    modelTermDict::Dict{AbstractString,ModelTerm} #key: "1:A*B" value: ModelTerm; convert modelTerms above to dictionary
    lhsVec::Array{Symbol,1}                       #phenotypes: [:y1,:y2]
    covVec::Array{Symbol,1}                       #variables those are covariates

                                                  #MIXED MODEL EQUATIONS
    X                                             #incidence matrix
    ySparse                                       #phenotypes
    obsID::Array{AbstractString,1}                #IDs for phenotypes
    mmeLhs                                        #Lhs of Mixed Model Equations
    mmeRhs                                        #Rhs of Mixed Model Equations

                                                  #RANDOM EFFCTS
    pedTrmVec                                     #polygenic effects(pedigree): "1:Animal","1:Mat","2:Animal"
    ped                                           #PedModule.Pedigree
    Gi::Array{Float64,2}                          #inverse of genetic covariance matrix for pedTrmVec (multi-trait)
    GiOld::Array{Float64,2}                       #specific for lambda version of MME (single-trait)
    GiNew::Array{Float64,2}                       #specific for lambda version of MME (single-trait)
    scalePed

    rndTrmVec::Array{RandomEffect,1}              #General (including i.i.d.) random effects
                                                  #may merge pedTrmVec here

                                                  #RESIDUAL EFFECTS
    R::Array{Float64,2}                           #residual covariance matrix (multi-trait)
    missingPattern                                #for impuation of missing residual
    resVar                                        #for impuation of missing residual
    ROld::Float64                                 #residual variance (single-trait) for
    RNew::Float64                                 #lambda version of MME (single-trait)
    scaleRes                                      #scale parameters

    M                                             #GENOTYPES

    mmePos::Int64                                 #temporary value to record term position (start from 1)

    outputSamplesVec::Array{ModelTerm,1}          #for which location parameters to save MCMC samples

    df::DF                                        #prior degree of freedom

    output_ID
    output_genotypes
    output_X

    output

    MCMCinfo

    function MME(nModels,modelVec,modelTerms,dict,lhsVec,R,ν)
      if nModels==1 && typeof(R)==Float64             #single-trait
        return new(nModels,modelVec,modelTerms,dict,lhsVec,[],
                   0,0,[],0,0,
                   0,0,zeros(1,1),zeros(1,1),zeros(1,1),zeros(1,1),
                   [],
                   zeros(1,1),0,0,R,R,R*(ν-2)/ν,
                   0,
                   1,
                   [],
                   DF(ν,4,4,4),
                   0,0,Dict{String,Any}(),
                   0,
                   0)
      elseif nModels>1 && typeof(R)==Array{Float64,2} #multi-trait
        ν,k      = ν, nModels
        νR0      = ν + k
        scaleRes = R*(νR0 - k - 1)
        return new(nModels,modelVec,modelTerms,dict,lhsVec,[],
                   0,0,[],0,0,
                   0,0,zeros(1,1),zeros(1,1),zeros(1,1),zeros(1,1),
                   [],
                   R,0,0,0.0,0.0,scaleRes,
                   0,
                   1,
                   [],
                   DF(νR0,4,4,4),
                   0,0,Dict{String,Any}(),
                   0,
                   0)
      else
        error("Residual variance R should be a scalar for single-trait analyses or a matrix for multi-trait analyses.")
      end
    end
end
