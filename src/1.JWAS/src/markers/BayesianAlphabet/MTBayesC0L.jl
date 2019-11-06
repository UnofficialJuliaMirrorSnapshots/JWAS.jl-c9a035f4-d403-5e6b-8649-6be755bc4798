function sampleMarkerEffectsMTBayesL!(xArray,xpx,wArray,
                                      alphaArray,gammaArray,
                                      invR0,invG0)
    # function to sample effects
    # invR0 is inverse of R0
    # invG0 is inverse of G0

    function getGiFunction(gammaArray)
        f1(x,j,Gi)  = Gi ./ x[j]
        f2(x,j,Gi)  = Gi
        size(gammaArray,1)>1 ? f1 : f2
    end
    getGi = getGiFunction(gammaArray)
    nEffects = length(xArray)
    nTraits  = length(alphaArray)
    Lhs = zeros(nTraits,nTraits)
    Rhs = zeros(nTraits)
    β = zeros(nTraits)             # vector of effects for locus j across all traits
    for j=1:nEffects
        for k=1:nTraits
            β[k] = alphaArray[k][j]
        end
        oldβ = copy(β) #add for optimization
        x = xArray[j]
        # unadjust for locus j
        for trait = 1:nTraits
            #wArray[trait][:] = wArray[trait][:] + x*alphaArray[trait][j]
            #Rhs[trait] = dot(x,wArray[trait])
            Rhs[trait] = dot(x,wArray[trait])+xpx[j]*alphaArray[trait][j]
        end
        Rhs = invR0*Rhs
        Lhs = dot(x,x)*invR0 + getGi(gammaArray,j,invG0)
        for trait = 1:nTraits
            lhs  = Lhs[trait,trait]
            ilhs = 1/lhs
            rhs  = Rhs[trait] - (Lhs[trait,:]'β)[1]
            mu   = ilhs*rhs + β[trait]
            alphaArray[trait][j] = mu + randn()*sqrt(ilhs)
            β[trait] = alphaArray[trait][j]
        end
        # adjust for locus j
        for trait = 1:nTraits
            #wArray[trait][:] = wArray[trait][:] - x*alphaArray[trait][j]
            BLAS.axpy!(oldβ[trait]-β[trait],x,wArray[trait])
        end
    end
end

sampleMarkerEffectsMTBayesC0!(xArray,xpx,wArray,
                              alphaArray,invR0,invG0) =
  sampleMarkerEffectsMTBayesL!(xArray,xpx,wArray,alphaArray,[1.0],invR0,invG0)
