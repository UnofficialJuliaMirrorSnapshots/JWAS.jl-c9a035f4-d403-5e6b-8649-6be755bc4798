################################################################################
#Set specific ModelTerm as random using pedigree information
#e.g. Animal, Animal*Age, Maternal
################################################################################
"""
    set_random(mme::MME,randomStr::AbstractString,ped::Pedigree, G;df=4)

* set variables as random polygenic effects with pedigree information **ped** and
  variances **G** with degree of freedom **df**, defaulting to `4.0`.

```julia
#single-trait (example 1)
model_equation  = "y = intercept + age + animal"
model           = build_model(model_equation,R)
ped             = get_pedigree(pedfile)
G               = 1.6
set_random(model,"animal", ped, G)

#single-trait (example 2)
model_equation  = "y = intercept + age + animal + animal*age"
model           = build_model(model_equation,R)
ped             = get_pedigree(pedfile)
G               = [1.6   0.2
                   0.2  1.0]
set_random(model,"animal animal*age", ped,G)

#multi-trait
model_equations = "BW = intercept + age + sex + animal
                   CW = intercept + age + sex + animal"
model           = build_model(model_equations,R);
ped             = get_pedigree(pedfile);
G               = [6.72   2.84
                   2.84  8.41]
set_random(model,"animal",ped,G)
```
"""
function set_random(mme::MME,randomStr::AbstractString,ped::PedModule.Pedigree,G=false;df=4)
    if mme.ped == 0
      mme.ped = deepcopy(ped)
    else
      error("Pedigree information is already added. Polygenic effects can only be set for one time")
    end
    set_random(mme,randomStr,G,Vinv=mme.ped,df=df)
end
############################################################################
#Set specific ModelTerm as random  (Not specific for IID or A(pedigree))
#useful for imputaion residual in single-step methods (var(ϵ)^{-1}=A^{nn} )
############################################################################
"""
    set_random(mme::MME,randomStr::AbstractString,G;Vinv=0,names=[],df=4)

* set variables as random effects, defaulting to i.i.d effects, with variances **G** with
  degree of freedom **df**, defaulting to 4.0.
* the random effects are assumed to be i.i.d by default and it can be defined with any
  (inverse of) covariance structure **Vinv** with its index (row names) provided by **names**.

```julia
#single-trait (i.i.d randome effects)
model_equation  = "y = intercept + litter + sex"
model           = build_model(model_equation,R)
G               = 0.6
set_random(model,"litter",G)

#multi-trait (i.i.d randome effects)
model_equations = "BW = intercept + litter + sex
                   CW = intercept + litter + sex"
model           = build_model(model_equations,R);
G               = [3.72  1.84
                   1.84  3.41]
set_random(model,"litter",G)

#single-trait (randome effects with specific covariance structures)
model_equation  = "y = intercept + litter + sex"
model           = build_model(model_equation,R)
V               = [1.0  0.5 0.25
                   0.5  1.0 0.5
                   0.25 0.5 1.0]
G               = 0.6
set_random(model,"litter",G,Vinv=inv(V),names=[a1;a2;a3])
```
"""
function set_random(mme::MME,randomStr::AbstractString,G=false;Vinv=0,names=[],df=4.0)
    ############################################################################
    #Pre-Check
    ############################################################################
    if  G != false && !isposdef(G)
        error("The covariance matrix is not positive definite.")
    end
    names   = string.(names)
    G       = map(Float64,G)
    df      = Float64(df)
    ############################################################################
    #add trait names (model equation number) to variables;
    #e.g., "litter"=>"y1:litter";"ϵ"=>"y1:ϵ"
    #"animal" => "y1:animal"; "animal*age"=>"y1:animal*age"
    ############################################################################
    randTrmVec = split(randomStr," ",keepempty=false)  # ["litter" "group"]
    res = []
    for trm in randTrmVec                              # "litter"; "group"
      for (m,model) = enumerate(mme.modelVec)
        strVec  = split(model,['=','+'])
        strpVec = [strip(i) for i in strVec]
        if trm in strpVec || trm == "ϵ"
          mtrm= string(mme.lhsVec[m])*":"*trm
          res = [res;mtrm]
        else
          printstyled(trm," is not found in model equation ",string(m),".\n",bold=false,color=:green)
        end
      end
    end                                               # "y1:litter"; "y2:litter"; "y1:group"
    ############################################################################
    #Set type of model terms
    ############################################################################
    modelTerms = [mme.modelTermDict[trm] for trm in res]
    if typeof(Vinv)==PedModule.Pedigree
      [trm.random_type = "A" for trm in modelTerms]
      [trm.names = PedModule.getIDs(mme.ped) for trm in modelTerms]
    elseif Vinv != 0 && names != []
      [trm.random_type = "V" for trm in modelTerms]
      [trm.names = names for trm in modelTerms]
      # observed effects (e.g., data[!,:litter]) may be a subset of total random effect (i.e.,names)
    else
      [trm.random_type = "I" for trm in modelTerms]
      #names will be obtained from observed data
    end
    ############################################################################
    #Covariance among effects for the same individual
    ############################################################################
    if G == false #make G matrix of zeros to get prior from phenotypes later
      G = (length(res)==1 ? 0.0 : zeros(length(res),length(res)))
    end
    if typeof(G)<:Number ##single variable single-trait, convert scalar G to 1x1 matrix
      G=reshape([G],1,1)
    end
    if length(res) != size(G,1)
      error("Dimensions must match. The covariance matrix (G) should be a ",length(res)," x ",length(res)," matrix.\n")
    end
    #Gi            : multi-trait;
    #GiOld & GiNew : single-trait, allow multiple correlated effects in single-trait
    Gi = GiOld = GiNew = (isposdef(G) ? Symmetric(inv(G)) : G)
    ############################################################################
    #return random_effct type
    ############################################################################
    if typeof(Vinv)==PedModule.Pedigree
      Vinv  = PedModule.AInverse(mme.ped)
      mme.pedTrmVec = res
      mme.Gi = mme.GiOld = mme.GiNew = (isposdef(G) ? Symmetric(inv(G)) : G)
      ν, k  = Float64(df), size(mme.pedTrmVec,1)
      νG0   = ν + k
      mme.df.polygenic = νG0 #final df for this inverse wisahrt
      mme.scalePed     = G*(mme.df.polygenic - k - 1)
      random_type = "A"
    elseif Vinv != 0
      random_type = "V"
      if size(Vinv,1) != length(names) || length(unique(names)) != length(names)
        error("Wrong size or duplicated values in Vinv and names.")
      end
    else
      random_type = "I"
    end
    term_array   = res
    df           = df+length(term_array)
    scale        = G*(df-length(term_array)-1)  #G*(df-2)/df #from inv χ to inv-wishat
    randomEffect = RandomEffect(term_array,Gi,GiOld,GiNew,df,scale,Vinv,names,random_type)
    push!(mme.rndTrmVec,randomEffect)
    nothing
end
################################################################################
#ADD TO MIXED MODEL EQUATIONS FOR THE RANDOM EFFECTS PARTS
################################################################################
#Construct MME for random effects with specific covariance structures including
#1) pedigree-based random effects part, e.g., "animal" and "maternal"
#2) IID
#
#Single-trait:
#lamda version, e.g., litter(A) and groups(B), where A and B may not be next to each other in the design matrix
#1) use `set_random(model,"1:A 1:B",G)` to estimate cov(1:A,1:B) (requirement: A.names == B.names; similar to ped)
#2) use `set_random(model,"1:A",G1);`set_random(model,"1:B",G2)` to make 1:A and 1:B independent.
#
#Multi-trait:
#e.g., 1:litter, 2:litter
#
################################################################################
#NOTE: SINGLE TRAIT
#The equation Ai*(GiNew*RNew - GiOld*ROld) is used to update Ai part in LHS
#The 1st time to add Ai to set up MME,
#mme.GiOld == zeros(G),mme.GiNew == inv(G),mme.Rnew == mme.Rold= R
#After that, if variances are constant,
#mme.GiOld == mme.GiNew; mme.Rnew == mme.Rold
#If sampling genetic variances, mme.Ginew is updated with a new sample, then
#LHS is update as Ai*(GiNew*RNew - GiOld*ROld), then GiOld = Ginew
#if sample residual variances, similar approaches to update the LHS is used.
################################################################################
function addVinv(mme::MME)
    for random_term in mme.rndTrmVec
      term_array = random_term.term_array
      Vi         = (random_term.Vinv!=0) ? random_term.Vinv : SparseMatrixCSC{Float64}(I, mme.modelTermDict[term_array[1]].nLevels, mme.modelTermDict[term_array[1]].nLevels)
      for (i,termi) = enumerate(term_array)
          randTrmi   = mme.modelTermDict[termi]
          startPosi  = randTrmi.startPos
          endPosi    = startPosi + randTrmi.nLevels - 1
          for (j,termj) in enumerate(term_array)
            randTrmj    = mme.modelTermDict[termj]
            startPosj   = randTrmj.startPos
            endPosj     = startPosj + randTrmj.nLevels - 1
            #lamda version (single trait) or not (multi-trait)
            myaddVinv   = (mme.nModels!=1) ? (Vi*random_term.Gi[i,j]) : (Vi*(random_term.GiNew[i,j]*mme.RNew - random_term.GiOld[i,j]*mme.ROld))
            mme.mmeLhs[startPosi:endPosi,startPosj:endPosj] =
            mme.mmeLhs[startPosi:endPosi,startPosj:endPosj] + myaddVinv
          end
      end
    end
end
